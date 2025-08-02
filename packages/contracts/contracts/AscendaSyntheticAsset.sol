// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {FHE, externalEuint64, euint64, ebool} from "@fhevm/solidity/lib/FHE.sol";
import {ConfidentialFungibleToken} from "@openzeppelin/confidential-contracts/token/ConfidentialFungibleToken.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/IAscendaOracle.sol";

/**
 * @title AscendaSyntheticAsset
 * @dev Confidential synthetic tokens representing exposure to real-world assets
 * Each token represents a share of a real-world asset (AAPL, TSLA, etc.)
 */
contract AscendaSyntheticAsset is ConfidentialFungibleToken, Ownable {
    string public underlyingAsset; 
    IAscendaOracle public immutable oracle;
    
    mapping(address => bool) public authorizedMinters;
    
    uint256 public collateralizationRatio; 
    euint64 public totalCollateral; 
    
    event SyntheticMinted(address indexed to, euint64 amount, euint64 collateralLocked);
    event SyntheticBurned(address indexed from, euint64 amount, euint64 collateralReleased);
    event CollateralizationUpdated(uint256 newRatio);
    
    modifier onlyAuthorizedMinter() {
        require(authorizedMinters[msg.sender], "Not authorized minter");
        _;
    }
    
    constructor(
        string memory underlyingAsset_,
        string memory name_,
        string memory symbol_,
        string memory tokenURI_,
        address oracle_,
        uint256 collateralizationRatio_
    ) ConfidentialFungibleToken(name_, symbol_, tokenURI_) {
        underlyingAsset = underlyingAsset_;
        oracle = IAscendaOracle(oracle_);
        collateralizationRatio = collateralizationRatio_;
    }
    
    function setAuthorizedMinter(address minter, bool authorized) external onlyOwner {
        authorizedMinters[minter] = authorized;
    }
    
    function setCollateralizationRatio(uint256 newRatio) external onlyOwner {
        require(newRatio >= 100, "Ratio must be >= 100%");
        collateralizationRatio = newRatio;
        emit CollateralizationUpdated(newRatio);
    }
    
    /**
     * @dev Mint synthetic tokens backed by collateral
     */
    function mintSynthetic(
        address to,
        euint64 syntheticAmount,
        euint64 collateralAmount
    ) external onlyAuthorizedMinter returns (euint64) {
        require(_isProperlyCollateralized(syntheticAmount, collateralAmount), "Insufficient collateral");
        
        totalCollateral = FHE.add(totalCollateral, collateralAmount);
        FHE.allowThis(totalCollateral);
        
        euint64 minted = _mint(to, syntheticAmount);
        
        emit SyntheticMinted(to, minted, collateralAmount);
        return minted;
    }
    
    /**
     * @dev Burn synthetic tokens and release collateral
     */
    function burnSynthetic(
        address from,
        euint64 syntheticAmount
    ) external onlyAuthorizedMinter returns (euint64 collateralReleased) {
        collateralReleased = _calculateCollateralRelease(syntheticAmount);
        
        totalCollateral = FHE.sub(totalCollateral, collateralReleased);
        FHE.allowThis(totalCollateral);
        
        euint64 burned = _burn(from, syntheticAmount);
        
        emit SyntheticBurned(from, burned, collateralReleased);
    }
    
    /**
     * @dev Get current asset price from oracle
     */
    function getCurrentPrice() external view returns (uint256) {
        IAscendaOracle.PriceData memory priceData = oracle.getPrice(underlyingAsset);
        require(priceData.isValid, "Invalid price data");
        return priceData.price;
    }
    
    /**
     * @dev Check if position is properly collateralized
     */
    function _isProperlyCollateralized(
        euint64 syntheticAmount,
        euint64 collateralAmount
    ) internal view returns (bool) {
        uint256 currentPrice = getCurrentPrice();
        
        euint64 syntheticValue = FHE.mul(syntheticAmount, FHE.asEuint64(currentPrice));
        euint64 requiredCollateral = FHE.mul(
            syntheticValue,
            FHE.asEuint64(collateralizationRatio)
        );
        requiredCollateral = FHE.div(requiredCollateral, FHE.asEuint64(100));
        
        return FHE.decrypt(FHE.gte(collateralAmount, requiredCollateral));
    }
    
    /**
     * @dev Calculate collateral to release when burning
     */
    function _calculateCollateralRelease(
        euint64 syntheticAmount
    ) internal view returns (euint64) {
        euint64 totalSupply = confidentialTotalSupply();
        euint64 proportion = FHE.div(syntheticAmount, totalSupply);
        return FHE.mul(totalCollateral, proportion);
    }
}