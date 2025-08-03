const { buildModule } = require("@nomicfoundation/hardhat-ignition/modules");

module.exports = buildModule("AscendaProtocolModule", (m) => {
  
  const admin = m.getParameter("admin", "0xA1a9E8c73Ecf86AE7F4858D5Cb72E689cDc9eb3e");
  const treasury = m.getParameter("treasury", "0xA1a9E8c73Ecf86AE7F4858D5Cb72E689cDc9eb3e");
  const insuranceFund = m.getParameter("insuranceFund", "0xA1a9E8c73Ecf86AE7F4858D5Cb72E689cDc9eb3e");
  const feeRecipient = m.getParameter("feeRecipient", "0xA1a9E8c73Ecf86AE7F4858D5Cb72E689cDc9eb3e");
  
  const underlyingToken = m.getParameter("underlyingToken", "0x4C2AA252BEe766D3399850569713b55178934849");
  const fusionProtocol = m.getParameter("fusionProtocol", "0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9");
  const limitOrderProtocol = m.getParameter("limitOrderProtocol", "0xDc64a140Aa3E981100a9becA4E685f962f0cF6C9");
  
  const collateralName = m.getParameter("collateralName", "Ascenda Confidential USDC");
  const collateralSymbol = m.getParameter("collateralSymbol", "acUSDC");
  const collateralTokenURI = m.getParameter("collateralTokenURI", "https://ascenda.finance/tokens/acusdc");
  
  const syntheticUnderlying = m.getParameter("syntheticUnderlying", "Tezos");
  const syntheticName = m.getParameter("syntheticName", "Ascenda Synthetic Tezos");
  const syntheticSymbol = m.getParameter("syntheticSymbol", "aTEZ");
  const syntheticTokenURI = m.getParameter("syntheticTokenURI", "https://ascenda.finance/tokens/atez");
  const collateralizationRatio = m.getParameter("collateralizationRatio", 150);

  const oracle = m.contract("AscendaOracle", [], {
    id: "AscendaOracle"
  });

  const confidentialCollateral = m.contract("AscendaConfidentialCollateral", [
    underlyingToken,
    collateralName,
    collateralSymbol,
    collateralTokenURI
  ], {
    id: "AscendaConfidentialCollateral",
    after: [oracle]
  });

  const derivativesEngine = m.contract("AscendaDerivativesEngine", [
    oracle,
    confidentialCollateral
  ], {
    id: "AscendaDerivativesEngine",
    after: [oracle, confidentialCollateral]
  });

  const syntheticAsset = m.contract("AscendaSyntheticAsset", [
    syntheticUnderlying,
    syntheticName,
    syntheticSymbol,
    syntheticTokenURI,
    oracle,
    collateralizationRatio
  ], {
    id: "AscendaSyntheticAsset",
    after: [oracle]
  });

  const crossChainSettlement = m.contract("CrossChainSettlementManager", [
    derivativesEngine,
    confidentialCollateral,
    fusionProtocol,
    treasury,
    insuranceFund,
    admin
  ], {
    id: "CrossChainSettlementManager",
    after: [derivativesEngine, confidentialCollateral]
  });

  const limitOrderManager = m.contract("LimitOrderManager", [
    derivativesEngine,
    confidentialCollateral,
    limitOrderProtocol,
    feeRecipient,
    admin
  ], {
    id: "LimitOrderManager",
    after: [derivativesEngine, confidentialCollateral]
  });

  const setOracleAuth = m.call(oracle, "setAuthorized", [admin, true], {
    id: "SetOracleAuthorized",
    after: [oracle]
  });

  const setBTCPrice = m.call(oracle, "updatePrice", ["BTC", "4500000000000"], {
    id: "SetInitialBTCPrice",
    after: [setOracleAuth]
  });

  const setETHPrice = m.call(oracle, "updatePrice", ["ETH", "300000000000"], {
    id: "SetInitialETHPrice", 
    after: [setBTCPrice]
  });

  const setUSDCPrice = m.call(oracle, "updatePrice", ["USDC", "1000000"], {
    id: "SetInitialUSDCPrice",
    after: [setETHPrice]
  });

  const setTEZOPrice = m.call(oracle, "updatePrice", ["TEZO", "2000000000"], {
    id: "SetInitialTEZOPrice",
    after: [setUSDCPrice]
  });

  const authDerivatives = m.call(confidentialCollateral, "setContractAuthorization", [derivativesEngine, true], {
    id: "AuthorizeDerivativesEngine",
    after: [confidentialCollateral, derivativesEngine, setTEZOPrice]
  });

  const authCrossChain = m.call(confidentialCollateral, "setContractAuthorization", [crossChainSettlement, true], {
    id: "AuthorizeCrossChainSettlement",
    after: [crossChainSettlement, authDerivatives]
  });

  const authLimitOrder = m.call(confidentialCollateral, "setContractAuthorization", [limitOrderManager, true], {
    id: "AuthorizeLimitOrderManager",
    after: [limitOrderManager, authCrossChain]
  });

  const addSynthetic = m.call(derivativesEngine, "addSyntheticAsset", ["TEZO", syntheticAsset], {
    id: "AddTEZOSynthetic",
    after: [derivativesEngine, syntheticAsset, authLimitOrder]
  });

  const authMinter = m.call(syntheticAsset, "setAuthorizedMinter", [derivativesEngine, true], {
    id: "AuthorizeSyntheticMinter",
    after: [syntheticAsset, addSynthetic]
  });

  return {
    oracle,
    confidentialCollateral,
    derivativesEngine,
    syntheticAsset,
    crossChainSettlement,
    limitOrderManager,
    
    config: {
      admin,
      treasury,
      insuranceFund,
      feeRecipient,
      underlyingToken,
      fusionProtocol,
      limitOrderProtocol,
      collateralizationRatio
    }
  };
});
