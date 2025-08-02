// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {FHE, externalEuint64, euint64, ebool} from "@fhevm/solidity/lib/FHE.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./AscendaConfidentialCollateral.sol";
import "./AscendaSyntheticAsset.sol";
import "../interfaces/IAscendaOracle.sol";

/**
 * @title AscendaDerivativesEngine
 * @dev Derivatives engine using confidential tokens for complete privacy
 */
contract AscendaDerivativesEngine is Ownable, ReentrancyGuard {
    using FHE for euint64;
    using FHE for ebool;
     using FHE for *;


    struct ConfidentialPosition {
        uint256 positionId;
        address owner;
        string underlying;
        PositionType positionType;
        euint64 quantity;
        euint64 strikePrice;
        euint64 premium;
        uint256 expiration;
        euint64 collateralAmount;
        PositionStatus status;
        uint256 createdAt;
        uint256 closedAt;
    }

    enum PositionType { CALL, PUT, FUTURE, SWAP }
    enum PositionStatus { OPEN, CLOSED, EXPIRED, LIQUIDATED }

    mapping(uint256 => ConfidentialPosition) public positions;
    mapping(address => uint256[]) public userPositions;
    mapping(string => bool) public supportedAssets;
    mapping(string => address) public syntheticAssets;

    uint256 private _positionIdCounter;

    IAscendaOracle public immutable oracle;
    AscendaConfidentialCollateral public immutable confidentialCollateral;

    event PositionOpened(
        uint256 indexed positionId,
        address indexed owner,
        string underlying,
        PositionType positionType,
        uint256 expiration
    );

    event SyntheticAssetAdded(string indexed underlying, address syntheticAsset);

    constructor(address oracle_, address confidentialCollateral_)
        Ownable(){
        oracle = IAscendaOracle(oracle_);
        confidentialCollateral = AscendaConfidentialCollateral(confidentialCollateral_);
    }

    function addSyntheticAsset(
        string memory underlying,
        address syntheticAsset
    ) external onlyOwner {
        require(!supportedAssets[underlying], "Asset already supported");
        supportedAssets[underlying] = true;
        syntheticAssets[underlying] = syntheticAsset;
        emit SyntheticAssetAdded(underlying, syntheticAsset);
    }

    function openConfidentialPosition(
        string calldata underlying,
        PositionType positionType,
        externalEuint64  encryptedQuantity,
        externalEuint64  encryptedStrikePrice,
        externalEuint64  encryptedPremium,
        uint256 expiration,
        externalEuint64  encryptedCollateral,
        bytes calldata quantityProof,
        bytes calldata strikePriceProof,
        bytes calldata premiumProof,
        bytes calldata collateralProof
    ) external nonReentrant returns (uint256 positionId) {
        require(supportedAssets[underlying], "Asset not supported");
        require(expiration > block.timestamp, "Invalid expiration");

        euint64 quantity = FHE.fromExternal(encryptedQuantity, quantityProof);
        euint64 strikePrice = FHE.fromExternal(encryptedStrikePrice, strikePriceProof);
        euint64 premium = FHE.fromExternal(encryptedPremium, premiumProof);
        euint64 collateral = FHE.fromExternal(encryptedCollateral, collateralProof);

        confidentialCollateral.authorizedTransfer(msg.sender, address(this), collateral);

        positionId = ++_positionIdCounter;

        positions[positionId] = ConfidentialPosition({
            positionId: positionId,
            owner: msg.sender,
            underlying: underlying,
            positionType: positionType,
            quantity: quantity,
            strikePrice: strikePrice,
            premium: premium,
            expiration: expiration,
            collateralAmount: collateral,
            status: PositionStatus.OPEN,
            createdAt: block.timestamp,
            closedAt: 0
        });

        userPositions[msg.sender].push(positionId);

        FHE.allow(quantity, msg.sender);
        FHE.allow(strikePrice, msg.sender);
        FHE.allow(premium, msg.sender);
        FHE.allow(collateral, msg.sender);

        emit PositionOpened(positionId, msg.sender, underlying, positionType, expiration);
    }

    function closeConfidentialPosition(
        uint256 positionId
    ) external nonReentrant {
        ConfidentialPosition storage position = positions[positionId];
        require(position.owner == msg.sender, "Not position owner");
        require(position.status == PositionStatus.OPEN, "Position not open");
        require(position.expiration >= block.timestamp, "Position expired");

        IAscendaOracle.PriceData memory priceData = oracle.getPrice(position.underlying);
        require(priceData.isValid, "Invalid price data");

        euint64 currentPrice = FHE.asEuint64(priceData.price);
        euint64 pnl = _calculateConfidentialPnL(position, currentPrice);
        euint64 settlementAmount = FHE.add(position.collateralAmount, pnl);

        confidentialCollateral.authorizedTransfer(address(this), msg.sender, settlementAmount);

        position.status = PositionStatus.CLOSED;
        position.closedAt = block.timestamp;

        FHE.allow(pnl, msg.sender);
        FHE.allow(settlementAmount, msg.sender);
    }

    function createSyntheticExposure(
        string calldata underlying,
        euint64 exposureAmount,
        euint64 collateralAmount
    ) external nonReentrant returns (euint64) {
        require(supportedAssets[underlying], "Asset not supported");

        address syntheticAsset = syntheticAssets[underlying];
        require(syntheticAsset != address(0), "No synthetic asset");

        confidentialCollateral.authorizedTransfer(msg.sender, address(this), collateralAmount);

        AscendaSyntheticAsset synthetic = AscendaSyntheticAsset(syntheticAsset);
        euint64 minted = synthetic.mintSynthetic(msg.sender, exposureAmount, collateralAmount);

        FHE.allow(minted, msg.sender);
        return minted;
    }

    function getConfidentialPortfolioValue(
        address user
    ) external view returns (euint64 totalValue) {
        uint256[] memory userPositionIds = userPositions[user];
        totalValue = FHE.asEuint64(0);

        for (uint256 i = 0; i < userPositionIds.length; i++) {
            ConfidentialPosition memory position = positions[userPositionIds[i]];
            if (position.status == PositionStatus.OPEN && position.expiration >= block.timestamp) {
                euint64 positionValue = _getPositionValue(position);
                totalValue = FHE.add(totalValue, positionValue);
            }
        }

        FHE.allow(totalValue, user);
        return totalValue;
    }

    function _calculateConfidentialPnL(
        ConfidentialPosition memory position,
        euint64 currentPrice
    ) internal pure returns (euint64) {
        euint64 zero = FHE.asEuint64(0);
        euint64 payoff;

        if (position.positionType == PositionType.CALL) {
            ebool inTheMoney = currentPrice.gt(position.strikePrice);
            euint64 intrinsicValue = currentPrice.sub(position.strikePrice);
            payoff = FHE.select(inTheMoney, intrinsicValue, zero);
        } else if (position.positionType == PositionType.PUT) {
            ebool inTheMoney = position.strikePrice.gt(currentPrice);
            euint64 intrinsicValue = position.strikePrice.sub(currentPrice);
            payoff = FHE.select(inTheMoney, intrinsicValue, zero);
        } else {
            return zero;
        }

        euint64 totalPayoff = payoff.mul(position.quantity);
        return totalPayoff.sub(position.premium);
    }

    function _getPositionValue(
        ConfidentialPosition memory position
    ) internal view returns (euint64) {
        IAscendaOracle.PriceData memory priceData = oracle.getPrice(position.underlying);
        if (!priceData.isValid) return position.collateralAmount;

        euint64 currentPrice = FHE.asEuint64(priceData.price);
        euint64 pnl = _calculateConfidentialPnL(position, currentPrice);
        return FHE.add(position.collateralAmount, pnl);
    }
}
