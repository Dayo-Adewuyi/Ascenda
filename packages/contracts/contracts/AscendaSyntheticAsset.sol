// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {FHE, euint64, ebool} from "@fhevm/solidity/lib/FHE.sol";
import {ConfidentialFungibleToken} from "@openzeppelin/confidential-contracts/token/ConfidentialFungibleToken.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "../interfaces/IAscendaOracle.sol";

contract AscendaSyntheticAsset is 
    ConfidentialFungibleToken, 
    Ownable, 
    Pausable, 
    ReentrancyGuard 
{
    using FHE for euint64;
    using FHE for ebool;

    string public underlyingAsset;
    IAscendaOracle public immutable oracle;

    mapping(address => bool) public authorizedMinters;

    uint256 public collateralizationRatio;
    uint256 public constant MIN_COLLATERAL_RATIO = 110;
    uint256 public constant MAX_COLLATERAL_RATIO = 500;

    euint64 public totalCollateral;
    
    mapping(address => euint64) public userSyntheticBalances;
    mapping(address => euint64) public userCollateralLocked;
    mapping(address => uint256) public userLastUpdate;

    uint256 public maxPriceAge = 3600;

    mapping(uint256 => address) private _collateralValidationRequests;

    event SyntheticMinted(address indexed to, euint64 amount, euint64 collateral, uint256 price);
    event SyntheticBurned(address indexed from, euint64 amount, euint64 collateral, uint256 price);
    event CollateralizationUpdated(uint256 newRatio);
    event AuthorizedMinterSet(address indexed minter, bool authorized);

    error InvalidCollateralizationRatio();
    error NotAuthorizedMinter();
    error InsufficientCollateral();
    error InvalidPriceData();
    error PriceTooOld();
    error InvalidAddress();

    modifier onlyAuthorizedMinter() {
        if (!authorizedMinters[msg.sender] && msg.sender != owner()) {
            revert NotAuthorizedMinter();
        }
        _;
    }

    modifier validAddress(address addr) {
        if (addr == address(0)) revert InvalidAddress();
        _;
    }

    constructor(
        string memory underlyingAsset_,
        string memory name_,
        string memory symbol_,
        string memory tokenURI_,
        address oracle_,
        uint256 collateralizationRatio_
    ) 
        ConfidentialFungibleToken(name_, symbol_, tokenURI_) 
        Ownable(msg.sender) 
    {
        if (oracle_ == address(0)) revert InvalidAddress();
        if (collateralizationRatio_ < MIN_COLLATERAL_RATIO || 
            collateralizationRatio_ > MAX_COLLATERAL_RATIO) {
            revert InvalidCollateralizationRatio();
        }

        underlyingAsset = underlyingAsset_;
        oracle = IAscendaOracle(oracle_);
        collateralizationRatio = collateralizationRatio_;
        
        totalCollateral = FHE.asEuint64(0);
        FHE.allowThis(totalCollateral);
    }

    function getCurrentPrice() public view returns (uint256 price, uint256 timestamp) {
        IAscendaOracle.PriceData memory priceData = oracle.getPrice(underlyingAsset);
        if (!priceData.isValid) revert InvalidPriceData();
        if (block.timestamp - priceData.timestamp > maxPriceAge) revert PriceTooOld();
        return (priceData.price, priceData.timestamp);
    }

    function setAuthorizedMinter(address minter, bool authorized) 
        external 
        onlyOwner 
        validAddress(minter) 
    {
        authorizedMinters[minter] = authorized;
        emit AuthorizedMinterSet(minter, authorized);
    }

    function setCollateralizationRatio(uint256 newRatio) external onlyOwner {
        if (newRatio < MIN_COLLATERAL_RATIO || newRatio > MAX_COLLATERAL_RATIO) {
            revert InvalidCollateralizationRatio();
        }
        collateralizationRatio = newRatio;
        emit CollateralizationUpdated(newRatio);
    }

    function mintSynthetic(
        address to,
        euint64 syntheticAmount,
        euint64 collateralAmount
    ) 
        external 
        onlyAuthorizedMinter 
        whenNotPaused 
        nonReentrant
        validAddress(to)
        returns (euint64 minted) 
    {
        (uint256 currentPrice,) = getCurrentPrice();
        _validateCollateralAsync(syntheticAmount, collateralAmount, currentPrice, msg.sender);
        userSyntheticBalances[to] = userSyntheticBalances[to].add(syntheticAmount);
        userCollateralLocked[to] = userCollateralLocked[to].add(collateralAmount);
        userLastUpdate[to] = block.timestamp;
        totalCollateral = totalCollateral.add(collateralAmount);
        FHE.allowThis(totalCollateral);
        FHE.allowThis(userSyntheticBalances[to]);
        FHE.allowThis(userCollateralLocked[to]);
        minted = _mint(to, syntheticAmount);
        emit SyntheticMinted(to, minted, collateralAmount, currentPrice);
        return minted;
    }

    function burnSynthetic(
        address from,
        euint64 syntheticAmount
    ) 
        external 
        onlyAuthorizedMinter 
        whenNotPaused 
        nonReentrant
        validAddress(from)
        returns (euint64 collateralReleased) 
    {
        (uint256 currentPrice,) = getCurrentPrice();
        collateralReleased = _calculateCollateralReleaseSimple(from, syntheticAmount);
        userSyntheticBalances[from] = userSyntheticBalances[from].sub(syntheticAmount);
        userCollateralLocked[from] = userCollateralLocked[from].sub(collateralReleased);
        userLastUpdate[from] = block.timestamp;
        totalCollateral = totalCollateral.sub(collateralReleased);
        FHE.allowThis(totalCollateral);
        FHE.allowThis(userSyntheticBalances[from]);
        FHE.allowThis(userCollateralLocked[from]);
        euint64 burned = _burn(from, syntheticAmount);
        emit SyntheticBurned(from, burned, collateralReleased, currentPrice);
        return collateralReleased;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function setMaxPriceAge(uint256 newMaxAge) external onlyOwner {
        require(newMaxAge > 0 && newMaxAge <= 24 hours, "Invalid max price age");
        maxPriceAge = newMaxAge;
    }

    function getUserPosition(address user) 
        external 
        view 
        returns (euint64 syntheticBalance, euint64 collateralLocked, uint256 lastUpdate) 
    {
        return (userSyntheticBalances[user], userCollateralLocked[user], userLastUpdate[user]);
    }

    function _validateCollateralAsync(
        euint64 syntheticAmount,
        euint64 collateralAmount,
        uint256 price,
        address requester
    ) internal {
        euint64 priceE = FHE.asEuint64(SafeCast.toUint64(price));
        euint64 syntheticValue = syntheticAmount.mul(priceE);
        euint64 leftSide = collateralAmount.mul(FHE.asEuint64(100));
        euint64 rightSide = syntheticValue.mul(FHE.asEuint64(SafeCast.toUint64(collateralizationRatio)));
        ebool isInsufficient = leftSide.lt(rightSide);
        bytes32[] memory cts = new bytes32[](1);
        cts[0] = ebool.unwrap(isInsufficient);
        uint256 requestId = FHE.requestDecryption(cts, this.finalizeCollateralValidation.selector);
        _collateralValidationRequests[requestId] = requester;
    }

    function finalizeCollateralValidation(uint256 requestId, uint64 result, bytes[] calldata signatures) external {
        FHE.checkSignatures(requestId, signatures);
        address requester = _collateralValidationRequests[requestId];
        require(requester != address(0), "Invalid decryption request");
        delete _collateralValidationRequests[requestId];
        if (result != 0) {
            revert InsufficientCollateral();
        }
    }

function _calculateCollateralReleaseSimple(
    address user,
    euint64 syntheticToBurn
) internal view returns (euint64) {
    euint64 userSynthetic = userSyntheticBalances[user];
    euint64 userCollateral = userCollateralLocked[user];
    
    ebool isBurningAll = FHE.eq(syntheticToBurn, userSynthetic);
    
    euint64 halfSynthetic = FHE.mul(userSynthetic, FHE.asEuint64(50));
    euint64 burnScaled = FHE.mul(syntheticToBurn, FHE.asEuint64(100));
    ebool isBurningHalf = FHE.eq(burnScaled, halfSynthetic);
    
    euint64 allCollateralResult = userCollateral;
    
    euint64 halfCollateralResult = FHE.mul(userCollateral, FHE.asEuint64(50));
    
    euint64 defaultResult = FHE.mul(userCollateral, FHE.asEuint64(25));
    euint64 halfOrDefault = FHE.select(isBurningHalf, halfCollateralResult, defaultResult);
    euint64 finalResult = FHE.select(isBurningAll, allCollateralResult, halfOrDefault);
    
    return finalResult;
}
}
