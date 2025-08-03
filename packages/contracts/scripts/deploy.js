const hre = require("hardhat");

async function main() {
  console.log("🚀 Starting Minimal Ascenda Deployment...");
  
  // Get signers
  const [deployer] = await hre.ethers.getSigners();
  console.log("Deploying with account:", deployer.address);
  console.log("Account balance:", hre.ethers.formatEther(await deployer.provider.getBalance(deployer.address)));

  // Basic parameters
  const admin = "0x4C3CB0eD1098b4848cB2590E7c7020958037F340";
  const underlyingToken = "0x4C2AA252BEe766D3399850569713b55178934849";

  try {
    // 1. Deploy Oracle
    console.log("\n📊 Deploying Oracle...");
    const Oracle = await hre.ethers.getContractFactory("AscendaOracle");
    
    const deployData = Oracle.interface.encodeDeploy([]);
    const gasEstimate = await deployer.provider.estimateGas({
      data: deployData,
    });
    console.log(`Estimated gas for Oracle: ${gasEstimate.toString()}`);
    
    const oracle = await Oracle.deploy();
    await oracle.waitForDeployment();
    console.log("✅ Oracle deployed to:", await oracle.getAddress());

    await new Promise(resolve => setTimeout(resolve, 5000));
    
    console.log("Setting oracle authorization...");
    let tx = await oracle.setAuthorized(admin, true, { gasLimit: 900000 });
    await tx.wait();
    console.log("✅ Oracle authorization set");

    await new Promise(resolve => setTimeout(resolve, 3000));
    
    console.log("Setting TEZO price...");
    tx = await oracle.updatePrice("TEZO", "200000000", { gasLimit: 900000 });
    await tx.wait();
    console.log("✅ TEZO price set");

    // 2. Deploy Confidential Collateral
    console.log("\n💰 Deploying Confidential Collateral...");
    const ConfidentialCollateral = await hre.ethers.getContractFactory("AscendaConfidentialCollateral");
    
    const collateralGasEstimate = await deployer.provider.estimateGas({
      data: ConfidentialCollateral.interface.encodeDeploy([
        underlyingToken,
        "Ascenda Confidential USDC",
        "acUSDC",
        "https://ascenda.finance/tokens/acusdc"
      ]),
    });
    console.log(`Estimated gas for Confidential Collateral: ${collateralGasEstimate.toString()}`);
    
    const confidentialCollateral = await ConfidentialCollateral.deploy(
      underlyingToken,
      "Ascenda Confidential USDC",
      "acUSDC",
      "https://ascenda.finance/tokens/acusdc",
    );
    await confidentialCollateral.waitForDeployment();
    console.log("✅ Confidential Collateral deployed to:", await confidentialCollateral.getAddress());

    // 3. Deploy Derivatives Engine
    console.log("\n🎯 Deploying Derivatives Engine...");
    const DerivativesEngine = await hre.ethers.getContractFactory("AscendaDerivativesEngine");
    
    await new Promise(resolve => setTimeout(resolve, 5000));
    
    const derivativesGasEstimate = await deployer.provider.estimateGas({
      data: DerivativesEngine.interface.encodeDeploy([
        await oracle.getAddress(),
        await confidentialCollateral.getAddress()
      ]),
    });
    console.log(`Estimated gas for Derivatives Engine: ${derivativesGasEstimate.toString()}`);
    
    const derivativesEngine = await DerivativesEngine.deploy(
      await oracle.getAddress(),
      await confidentialCollateral.getAddress(),
    );
    await derivativesEngine.waitForDeployment();
    console.log("✅ Derivatives Engine deployed to:", await derivativesEngine.getAddress());

    // 4. Setup Authorization
    console.log("\n🔐 Setting up authorization...");
    await new Promise(resolve => setTimeout(resolve, 5000));
    
    tx = await confidentialCollateral.setContractAuthorization(await derivativesEngine.getAddress(), true, {
      gasLimit: 500000,
    });
    await tx.wait();
    console.log("✅ Derivatives Engine authorized");

    // Final summary
    console.log("\n🎉 MINIMAL DEPLOYMENT COMPLETED! 🎉");
    console.log("\n📋 Core Contract Addresses:");
    console.log("=".repeat(40));
    console.log(`Oracle:                  ${await oracle.getAddress()}`);
    console.log(`Confidential Collateral: ${await confidentialCollateral.getAddress()}`);
    console.log(`Derivatives Engine:      ${await derivativesEngine.getAddress()}`);
    console.log("=".repeat(40));
    console.log("\n💡 To deploy remaining contracts, update these addresses in the full deployment script");

  } catch (error) {
    console.error("\n❌ Deployment failed:", error);
    console.error("Error details:", error.reason || error.message);
    
    // Print gas-related info if available
    if (error.data) {
      console.error("Error data:", error.data);
    }
    
    process.exit(1);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });