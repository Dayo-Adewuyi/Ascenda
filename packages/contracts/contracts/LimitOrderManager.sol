// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {FHE, externalEuint64, euint64, ebool} from "@fhevm/solidity/lib/FHE.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/ILimitOrderProtocol.sol";
import "./AscendaConfidentialCollateral.sol";
import "./AscendaDerivativesEngine.sol";

/**
 * @title LimitOrderManager
 * @notice Handles complex derivative strategies with full privacy preservation
 */
contract LimitOrderManager is AccessControl, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;
    using FHE for euint64;
    using FHE for ebool;
    using FHE for *;

    // ==================== CONSTANTS ====================

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");
    bytes32 public constant RESOLVER_ROLE = keccak256("RESOLVER_ROLE");

    uint256 public constant MAX_STRATEGY_LEGS = 6;
    uint256 public constant MIN_ORDER_LIFETIME = 1 hours;
    uint256 public constant MAX_ORDER_LIFETIME = 365 days;
    uint256 public constant MAX_SLIPPAGE_BPS = 1000;
    uint256 public constant EMERGENCY_WITHDRAWAL_DELAY = 7 days;
    uint256 public constant MIN_ORDER_QUANTITY = 1;
    uint256 public constant MIN_STRIKE_PRICE = 1;

    // ==================== ENUMS ====================

    enum OrderStatus {
        PENDING,
        PARTIALLY_FILLED,
        FILLED,
        CANCELLED,
        EXPIRED,
        FAILED
    }

    enum StrategyType {
        BULL_CALL_SPREAD,
        BEAR_PUT_SPREAD,
        BULL_PUT_SPREAD,
        BEAR_CALL_SPREAD,
        IRON_CONDOR,
        IRON_BUTTERFLY,
        STRADDLE,
        STRANGLE,
        COVERED_CALL,
        PROTECTIVE_PUT,
        COLLAR
    }

    // ==================== STRUCTS ====================

    struct ConfidentialOrder {
        uint256 orderId;
        address owner;
        string underlying;
        AscendaDerivativesEngine.PositionType positionType;
        euint64 quantity;
        euint64 strikePrice;
        euint64 limitPrice;
        euint64 stopPrice;
        euint64 maxSlippage;
        uint256 expiration;
        uint256 orderExpiration;
        euint64 collateralAmount;
        OrderStatus status;
        uint256 createdAt;
        uint256 lastUpdated;
        bytes32 limitOrderHash;
        bool isStopOrder;
        uint256 executedQuantity;
        uint256 estimatedQuantity;
        uint256 estimatedStrikePrice;
        uint256 estimatedLimitPrice;
        uint256 estimatedCollateral;
    }

    struct StrategyOrder {
        uint256 strategyId;
        address owner;
        StrategyType strategyType;
        string underlying;
        uint256[] legOrderIds;
        euint64 netPremium;
        euint64 maxLoss;
        euint64 maxProfit;
        OrderStatus status;
        uint256 createdAt;
        uint256 expiration;
        bool isCredit;
        uint256 estimatedNetPremium;
        uint256 estimatedMaxLoss;
        uint256 estimatedMaxProfit;
    }

    struct OrderValidation {
        bool isValid;
        string errorMessage;
        euint64 requiredCollateral;
        uint256 estimatedGas;
    }

    // ==================== STATE VARIABLES ====================

    mapping(uint256 => ConfidentialOrder) public orders;
    mapping(uint256 => StrategyOrder) public strategies;
    mapping(address => uint256[]) public userOrders;
    mapping(address => uint256[]) public userStrategies;
    mapping(bytes32 => uint256) public limitOrderToDerivativeOrder;
    mapping(address => euint64) public userLockedCollateral;
    mapping(address => uint256) public userEstimatedLockedCollateral; 
    mapping(uint256 => uint256) public orderToStrategy;

    mapping(address => uint256) public emergencyWithdrawalRequests;
    mapping(address => bool) public emergencyWithdrawalApproved;

    uint256 private _orderIdCounter;
    uint256 private _strategyIdCounter;

    AscendaDerivativesEngine public immutable derivativesEngine;
    AscendaConfidentialCollateral public immutable confidentialCollateral;
    ILimitOrderProtocol public limitOrderProtocol;

    uint256 public makerFeeBps = 25;
    uint256 public takerFeeBps = 50;
    uint256 public strategyFeeBps = 75;
    address public feeRecipient;

    uint256 public maxDailyVolume = 10_000_000e6;
    uint256 public dailyVolume;
    uint256 public lastVolumeResetDay;

    // ==================== EVENTS ====================

    event OrderCreated(
        uint256 indexed orderId,
        address indexed owner,
        string underlying,
        AscendaDerivativesEngine.PositionType positionType,
        uint256 expiration,
        bytes32 limitOrderHash
    );

    event OrderFilled(
        uint256 indexed orderId,
        address indexed owner,
        uint256 executedQuantity,
        uint256 averagePrice,
        uint256 positionId
    );

    event OrderPartiallyFilled(
        uint256 indexed orderId,
        uint256 filledQuantity,
        uint256 remainingQuantity
    );

    event OrderCancelled(
        uint256 indexed orderId,
        address indexed owner,
        string reason
    );

    event StrategyCreated(
        uint256 indexed strategyId,
        address indexed owner,
        StrategyType strategyType,
        uint256[] legOrderIds
    );

    event StrategyExecuted(
        uint256 indexed strategyId,
        address indexed owner,
        uint256[] positionIds
    );

    event EmergencyWithdrawalRequested(
        address indexed user,
        uint256 requestTime
    );

    event EmergencyWithdrawalExecuted(address indexed user, uint256 amount);

    event CircuitBreakerTriggered(
        uint256 dailyVolume,
        uint256 maxVolume,
        uint256 timestamp
    );

    event ParametersUpdated(
        uint256 makerFeeBps,
        uint256 takerFeeBps,
        uint256 strategyFeeBps,
        uint256 maxDailyVolume
    );

    // ==================== MODIFIERS ====================

    modifier onlyValidOrder(uint256 orderId) {
        require(orderId > 0 && orderId <= _orderIdCounter, "Invalid order ID");
        require(orders[orderId].owner != address(0), "Order does not exist");
        _;
    }

    modifier onlyOrderOwner(uint256 orderId) {
        require(orders[orderId].owner == msg.sender, "Not order owner");
        _;
    }

    modifier onlyValidStrategy(uint256 strategyId) {
        require(
            strategyId > 0 && strategyId <= _strategyIdCounter,
            "Invalid strategy ID"
        );
        require(
            strategies[strategyId].owner != address(0),
            "Strategy does not exist"
        );
        _;
    }

    modifier onlyStrategyOwner(uint256 strategyId) {
        require(
            strategies[strategyId].owner == msg.sender,
            "Not strategy owner"
        );
        _;
    }

    modifier whenNotCircuitBroken() {
        require(!_isCircuitBroken(), "Circuit breaker active");
        _;
    }

    modifier volumeCheck(uint256 notionalValue) {
        _updateDailyVolume(notionalValue);
        require(dailyVolume <= maxDailyVolume, "Daily volume limit exceeded");
        _;
    }

    // ==================== CONSTRUCTOR ====================

    constructor(
        address _derivativesEngine,
        address _confidentialCollateral,
        address _limitOrderProtocol,
        address _feeRecipient,
        address _admin
    ) {
        require(_derivativesEngine != address(0), "Invalid derivatives engine");
        require(_confidentialCollateral != address(0), "Invalid collateral");
        require(
            _limitOrderProtocol != address(0),
            "Invalid limit order protocol"
        );
        require(_feeRecipient != address(0), "Invalid fee recipient");
        require(_admin != address(0), "Invalid admin");

        derivativesEngine = AscendaDerivativesEngine(_derivativesEngine);
        confidentialCollateral = AscendaConfidentialCollateral(
            _confidentialCollateral
        );
        limitOrderProtocol = ILimitOrderProtocol(_limitOrderProtocol);
        feeRecipient = _feeRecipient;

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(OPERATOR_ROLE, _admin);
        _grantRole(EMERGENCY_ROLE, _admin);

        lastVolumeResetDay = block.timestamp / 1 days;
    }

    // ==================== EXTERNAL FUNCTIONS ====================

    /**
     * @notice Create a new confidential derivative order
     * @param underlying The underlying asset symbol
     * @param positionType The type of position (CALL, PUT, etc.)
     * @param encryptedQuantity Encrypted quantity of contracts
     * @param encryptedStrikePrice Encrypted strike price
     * @param encryptedLimitPrice Encrypted limit price for order execution
     * @param expiration Option expiration timestamp
     * @param orderLifetime How long the order remains active
     * @param encryptedCollateral Encrypted collateral amount
     * @param isStopOrder Whether this is a stop order
     * @param encryptedStopPrice Encrypted stop price (if stop order)
     * @param proofs Array of proofs for encrypted inputs
     * @param estimatedQuantity Public estimate of quantity for volume tracking
     * @param estimatedStrikePrice Public estimate of strike price
     * @param estimatedLimitPrice Public estimate of limit price
     * @param estimatedCollateral Public estimate of collateral
     */
    function createOrder(
        string calldata underlying,
        AscendaDerivativesEngine.PositionType positionType,
        externalEuint64 encryptedQuantity,
        externalEuint64 encryptedStrikePrice,
        externalEuint64 encryptedLimitPrice,
        uint256 expiration,
        uint256 orderLifetime,
        externalEuint64 encryptedCollateral,
        bool isStopOrder,
        externalEuint64 encryptedStopPrice,
        bytes[] calldata proofs,
        uint256 estimatedQuantity,
        uint256 estimatedStrikePrice,
        uint256 estimatedLimitPrice,
        uint256 estimatedCollateral
    )
        external
        nonReentrant
        whenNotPaused
        whenNotCircuitBroken
        returns (uint256 orderId)
    {
        require(bytes(underlying).length > 0, "Invalid underlying");
        require(expiration > block.timestamp, "Invalid expiration");
        require(
            orderLifetime >= MIN_ORDER_LIFETIME &&
                orderLifetime <= MAX_ORDER_LIFETIME,
            "Invalid order lifetime"
        );
        require(proofs.length >= 4, "Insufficient proofs");
        require(estimatedQuantity >= MIN_ORDER_QUANTITY, "Quantity too small");
        require(estimatedStrikePrice >= MIN_STRIKE_PRICE, "Strike price too small");

        euint64 quantity = FHE.fromExternal(encryptedQuantity, proofs[0]);
        euint64 strikePrice = FHE.fromExternal(encryptedStrikePrice, proofs[1]);
        euint64 limitPrice = FHE.fromExternal(encryptedLimitPrice, proofs[2]);
        euint64 collateral = FHE.fromExternal(encryptedCollateral, proofs[3]);
        euint64 stopPrice = isStopOrder
            ? FHE.fromExternal(encryptedStopPrice, proofs[4])
            : FHE.asEuint64(0);

        OrderValidation memory validation = _validateOrderWithEstimates(
            underlying,
            positionType,
            estimatedQuantity,
            estimatedStrikePrice,
            estimatedLimitPrice,
            estimatedCollateral,
            expiration
        );
        require(validation.isValid, validation.errorMessage);

        confidentialCollateral.authorizedTransfer(
            msg.sender,
            address(this),
            collateral
        );
        userLockedCollateral[msg.sender] = FHE.add(
            userLockedCollateral[msg.sender],
            collateral
        );
        userEstimatedLockedCollateral[msg.sender] += estimatedCollateral;

        orderId = ++_orderIdCounter;
        uint256 orderExpiration = block.timestamp + orderLifetime;

        orders[orderId] = ConfidentialOrder({
            orderId: orderId,
            owner: msg.sender,
            underlying: underlying,
            positionType: positionType,
            quantity: quantity,
            strikePrice: strikePrice,
            limitPrice: limitPrice,
            stopPrice: stopPrice,
            maxSlippage: FHE.asEuint64(SafeCast.toUint64(MAX_SLIPPAGE_BPS)),
            expiration: expiration,
            orderExpiration: orderExpiration,
            collateralAmount: collateral,
            status: OrderStatus.PENDING,
            createdAt: block.timestamp,
            lastUpdated: block.timestamp,
            limitOrderHash: bytes32(0),
            isStopOrder: isStopOrder,
            executedQuantity: 0,
            estimatedQuantity: estimatedQuantity,
            estimatedStrikePrice: estimatedStrikePrice,
            estimatedLimitPrice: estimatedLimitPrice,
            estimatedCollateral: estimatedCollateral
        });

        userOrders[msg.sender].push(orderId);

        bytes32 limitOrderHash = _createLimitOrder(orderId);
        orders[orderId].limitOrderHash = limitOrderHash;
        limitOrderToDerivativeOrder[limitOrderHash] = orderId;

        FHE.allow(quantity, msg.sender);
        FHE.allow(strikePrice, msg.sender);
        FHE.allow(limitPrice, msg.sender);
        FHE.allow(collateral, msg.sender);
        if (isStopOrder) {
            FHE.allow(stopPrice, msg.sender);
        }

        emit OrderCreated(
            orderId,
            msg.sender,
            underlying,
            positionType,
            expiration,
            limitOrderHash
        );
    }

    /**
     * @notice Execute/fill an order
     * @param orderId The order ID to execute
     * @param fillQuantity Quantity to fill (0 for full fill)
     * @param executionPrice Price at which order was executed
     */
    function executeOrder(
        uint256 orderId,
        uint256 fillQuantity,
        uint256 executionPrice
    )
        external
        onlyRole(RESOLVER_ROLE)
        nonReentrant
        whenNotPaused
        onlyValidOrder(orderId)
    {
        ConfidentialOrder storage order = orders[orderId];
        require(
            order.status == OrderStatus.PENDING,
            "Order not available for execution"
        );
        require(block.timestamp <= order.orderExpiration, "Order expired");
        require(executionPrice > 0, "Invalid execution price");

        uint256 maxFillQuantity = order.estimatedQuantity - order.executedQuantity;

        if (fillQuantity == 0) {
            fillQuantity = maxFillQuantity;
        }
        require(
            fillQuantity <= maxFillQuantity,
            "Fill quantity exceeds remaining"
        );
        require(fillQuantity > 0, "Invalid fill quantity");

        uint256 notionalValue = fillQuantity * executionPrice;
        uint256 fee = _calculateFee(notionalValue, false);

        _updateDailyVolume(notionalValue);

        uint256 positionId = _createDerivativePosition(
            order,
            fillQuantity,
            executionPrice
        );

        order.executedQuantity += fillQuantity;
        order.lastUpdated = block.timestamp;

        if (order.executedQuantity == order.estimatedQuantity) {
            order.status = OrderStatus.FILLED;
            userLockedCollateral[order.owner] = FHE.sub(
                userLockedCollateral[order.owner],
                order.collateralAmount
            );
            userEstimatedLockedCollateral[order.owner] -= order.estimatedCollateral;
        } else {
            order.status = OrderStatus.PARTIALLY_FILLED;
            
            uint256 collateralToReleaseEstimate = (order.estimatedCollateral * fillQuantity) / order.estimatedQuantity;
            
            
            euint64 collateralToRelease = FHE.asEuint64(SafeCast.toUint64(collateralToReleaseEstimate));
            
            userLockedCollateral[order.owner] = FHE.sub(
                userLockedCollateral[order.owner],
                collateralToRelease
            );
            userEstimatedLockedCollateral[order.owner] -= collateralToReleaseEstimate;

            emit OrderPartiallyFilled(
                orderId,
                fillQuantity,
                maxFillQuantity - fillQuantity
            );
        }

        if (fee > 0) {
            confidentialCollateral.authorizedTransfer(
                order.owner,
                feeRecipient,
                FHE.asEuint64(SafeCast.toUint64(fee))
            );
        }

        emit OrderFilled(
            orderId,
            order.owner,
            fillQuantity,
            executionPrice,
            positionId
        );
    }

    /**
     * @notice Cancel an active order
     * @param orderId The order ID to cancel
     * @param reason Reason for cancellation
     */
      function cancelOrder(
        uint256 orderId,
        string calldata reason
    ) external nonReentrant onlyValidOrder(orderId) {
        ConfidentialOrder storage order = orders[orderId];

        require(
            msg.sender == order.owner || hasRole(EMERGENCY_ROLE, msg.sender),
            "Not authorized to cancel"
        );

        require(
            order.status == OrderStatus.PENDING ||
                order.status == OrderStatus.PARTIALLY_FILLED,
            "Order cannot be cancelled"
        );

        order.status = OrderStatus.CANCELLED;
        order.lastUpdated = block.timestamp;

        euint64 collateralToRelease;
        uint256 estimatedCollateralToRelease;
        
        if (order.executedQuantity == 0) {
            collateralToRelease = order.collateralAmount;
            estimatedCollateralToRelease = order.estimatedCollateral;
        } else {
            uint256 remainingQuantity = order.estimatedQuantity - order.executedQuantity;
            estimatedCollateralToRelease = (order.estimatedCollateral * remainingQuantity) / order.estimatedQuantity;
            
            collateralToRelease = FHE.asEuint64(SafeCast.toUint64(estimatedCollateralToRelease));
        }

        userLockedCollateral[order.owner] = FHE.sub(
            userLockedCollateral[order.owner],
            collateralToRelease
        );
        userEstimatedLockedCollateral[order.owner] -= estimatedCollateralToRelease;
        
        confidentialCollateral.authorizedTransfer(
            address(this),
            order.owner,
            collateralToRelease
        );

        if (order.limitOrderHash != bytes32(0)) {
            _cancelLimitOrder(order.limitOrderHash);
        }

        emit OrderCancelled(orderId, order.owner, reason);
    }

    /**
     * @notice Create a multi-leg derivative strategy
     * @param strategyType Type of strategy to create
     * @param underlying Underlying asset for all legs
     * @param legParams Array of leg parameters [quantity, strike, limitPrice, collateral]
     * @param estimatedLegParams Array of estimated leg parameters for operations
     * @param expiration Strategy expiration
     * @param proofs Proofs for all encrypted inputs
     */
    function createStrategy(
        StrategyType strategyType,
        string calldata underlying,
        uint256[4][] calldata legParams,
        uint256[4][] calldata estimatedLegParams, 
        uint256 expiration,
        bytes[] calldata proofs
    )
        external
        nonReentrant
        whenNotPaused
        whenNotCircuitBroken
        returns (uint256 strategyId)
    {
        require(
            legParams.length >= 2 && legParams.length <= MAX_STRATEGY_LEGS,
            "Invalid number of legs"
        );
        require(legParams.length == estimatedLegParams.length, "Parameter length mismatch");
        require(bytes(underlying).length > 0, "Invalid underlying");
        require(expiration > block.timestamp, "Invalid expiration");
        require(proofs.length >= legParams.length * 4, "Insufficient proofs");

        require(
            _isValidStrategyType(strategyType, legParams.length),
            "Invalid strategy configuration"
        );

        strategyId = ++_strategyIdCounter;
        uint256[] memory legOrderIds = new uint256[](legParams.length);

        uint256 proofIndex = 0;
        for (uint256 i = 0; i < legParams.length; i++) {
            euint64 quantity = FHE.fromExternal(
                externalEuint64.wrap(bytes32(legParams[i][0])),
                proofs[proofIndex++]
            );
            euint64 strikePrice = FHE.fromExternal(
                externalEuint64.wrap(bytes32(legParams[i][1])),
                proofs[proofIndex++]
            );
            euint64 limitPrice = FHE.fromExternal(
                externalEuint64.wrap(bytes32(legParams[i][2])),
                proofs[proofIndex++]
            );
            euint64 collateral = FHE.fromExternal(
                externalEuint64.wrap(bytes32(legParams[i][3])),
                proofs[proofIndex++]
            );

            AscendaDerivativesEngine.PositionType positionType = _getPositionTypeForLeg(
                    strategyType,
                    i
                );

            uint256 legOrderId = _createStrategyLegOrder(
                underlying,
                positionType,
                quantity,
                strikePrice,
                limitPrice,
                expiration,
                collateral,
                estimatedLegParams[i] 
            );

            legOrderIds[i] = legOrderId;
            orderToStrategy[legOrderId] = strategyId;
        }

        require(
            _validateStrategyLogic(strategyType, legOrderIds),
            "Invalid strategy logic"
        );

        (
            euint64 netPremium,
            euint64 maxLoss,
            euint64 maxProfit,
            bool isCredit,
            uint256 estimatedNetPremium,
            uint256 estimatedMaxLoss,
            uint256 estimatedMaxProfit
        ) = _calculateStrategyMetrics(legOrderIds);

        strategies[strategyId] = StrategyOrder({
            strategyId: strategyId,
            owner: msg.sender,
            strategyType: strategyType,
            underlying: underlying,
            legOrderIds: legOrderIds,
            netPremium: netPremium,
            maxLoss: maxLoss,
            maxProfit: maxProfit,
            status: OrderStatus.PENDING,
            createdAt: block.timestamp,
            expiration: expiration,
            isCredit: isCredit,
            estimatedNetPremium: estimatedNetPremium,
            estimatedMaxLoss: estimatedMaxLoss,
            estimatedMaxProfit: estimatedMaxProfit
        });

        userStrategies[msg.sender].push(strategyId);

        FHE.allow(netPremium, msg.sender);
        FHE.allow(maxLoss, msg.sender);
        FHE.allow(maxProfit, msg.sender);

        emit StrategyCreated(strategyId, msg.sender, strategyType, legOrderIds);
    }

    /**
     * @notice Request emergency withdrawal of locked collateral
     * @dev Initiates a time-delayed withdrawal process for emergency situations
     */
    function requestEmergencyWithdrawal() external nonReentrant {
        require(
            !emergencyWithdrawalApproved[msg.sender],
            "Withdrawal already approved"
        );
        require(
            emergencyWithdrawalRequests[msg.sender] == 0,
            "Request already pending"
        );

        uint256 estimatedLockedAmount = userEstimatedLockedCollateral[msg.sender];
        require(estimatedLockedAmount > 0, "No locked collateral");

        emergencyWithdrawalRequests[msg.sender] = block.timestamp;

        emit EmergencyWithdrawalRequested(msg.sender, block.timestamp);
    }

    /**
     * @notice Execute emergency withdrawal after delay period
     */
    function executeEmergencyWithdrawal() external nonReentrant {
        uint256 requestTime = emergencyWithdrawalRequests[msg.sender];
        require(requestTime > 0, "No withdrawal request");
        require(
            block.timestamp >= requestTime + EMERGENCY_WITHDRAWAL_DELAY,
            "Withdrawal delay not met"
        );
        require(
            emergencyWithdrawalApproved[msg.sender] ||
                hasRole(EMERGENCY_ROLE, msg.sender),
            "Withdrawal not approved"
        );

        euint64 lockedAmount = userLockedCollateral[msg.sender];
        uint256 estimatedLockedAmount = userEstimatedLockedCollateral[msg.sender];
        
        require(estimatedLockedAmount > 0, "No locked collateral");

        emergencyWithdrawalRequests[msg.sender] = 0;
        emergencyWithdrawalApproved[msg.sender] = false;
        userLockedCollateral[msg.sender] = FHE.asEuint64(0);
        userEstimatedLockedCollateral[msg.sender] = 0;

        confidentialCollateral.authorizedTransfer(
            address(this),
            msg.sender,
            lockedAmount
        );

        emit EmergencyWithdrawalExecuted(msg.sender, estimatedLockedAmount);
    }

    // ==================== ADMIN FUNCTIONS ====================

    function setLimitOrderProtocol(
        address _limitOrderProtocol
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_limitOrderProtocol != address(0), "Invalid address");
        limitOrderProtocol = ILimitOrderProtocol(_limitOrderProtocol);
    }

    function updateFeeStructure(
        uint256 _makerFeeBps,
        uint256 _takerFeeBps,
        uint256 _strategyFeeBps,
        address _feeRecipient
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_makerFeeBps <= 100, "Maker fee too high");
        require(_takerFeeBps <= 200, "Taker fee too high");
        require(_strategyFeeBps <= 300, "Strategy fee too high");
        require(_feeRecipient != address(0), "Invalid fee recipient");

        makerFeeBps = _makerFeeBps;
        takerFeeBps = _takerFeeBps;
        strategyFeeBps = _strategyFeeBps;
        feeRecipient = _feeRecipient;

        emit ParametersUpdated(
            _makerFeeBps,
            _takerFeeBps,
            _strategyFeeBps,
            maxDailyVolume
        );
    }

    function updateMaxDailyVolume(
        uint256 _maxDailyVolume
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_maxDailyVolume > 0, "Invalid volume limit");
        maxDailyVolume = _maxDailyVolume;

        emit ParametersUpdated(
            makerFeeBps,
            takerFeeBps,
            strategyFeeBps,
            _maxDailyVolume
        );
    }

    function approveEmergencyWithdrawal(
        address user
    ) external onlyRole(EMERGENCY_ROLE) {
        require(emergencyWithdrawalRequests[user] > 0, "No withdrawal request");
        emergencyWithdrawalApproved[user] = true;
    }

    function pauseContract() external onlyRole(EMERGENCY_ROLE) {
        _pause();
    }

    function unpauseContract() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    // ==================== VIEW FUNCTIONS ====================

    function getUserOrders(
        address user
    ) external view returns (uint256[] memory) {
        return userOrders[user];
    }

    function getUserStrategies(
        address user
    ) external view returns (uint256[] memory) {
        return userStrategies[user];
    }

    function getOrder(
        uint256 orderId
    ) external view returns (ConfidentialOrder memory) {
        return orders[orderId];
    }

    function getStrategy(
        uint256 strategyId
    ) external view returns (StrategyOrder memory) {
        return strategies[strategyId];
    }

    function getUserLockedCollateral(
        address user
    ) external returns (euint64) {
        euint64 locked = userLockedCollateral[user];
        if (msg.sender == user) {
            FHE.allow(locked, user);
        }
        return locked;
    }

    function getUserEstimatedLockedCollateral(
        address user
    ) external view returns (uint256) {
        return userEstimatedLockedCollateral[user];
    }

    function getOrderCount() external view returns (uint256) {
        return _orderIdCounter;
    }

    function getStrategyCount() external view returns (uint256) {
        return _strategyIdCounter;
    }

    function isCircuitBroken() external view returns (bool) {
        return _isCircuitBroken();
    }

    // ==================== INTERNAL FUNCTIONS ====================

    function _validateOrderWithEstimates(
        string memory underlying,
        AscendaDerivativesEngine.PositionType positionType,
        uint256 estimatedQuantity,
        uint256 estimatedStrikePrice,
        uint256 estimatedLimitPrice,
        uint256 estimatedCollateral,
        uint256 expiration
    ) internal returns (OrderValidation memory) {
        if (!derivativesEngine.supportedAssets(underlying)) {
            return
                OrderValidation(
                    false,
                    "Asset not supported",
                    FHE.asEuint64(0),
                    0
                );
        }

        if (expiration <= block.timestamp + 1 hours) {
            return
                OrderValidation(
                    false,
                    "Expiration too soon",
                    FHE.asEuint64(0),
                    0
                );
        }

        if (estimatedQuantity == 0) {
            return
                OrderValidation(false, "Invalid quantity", FHE.asEuint64(0), 0);
        }

        if (estimatedStrikePrice == 0) {
            return
                OrderValidation(
                    false,
                    "Invalid strike price",
                    FHE.asEuint64(0),
                    0
                );
        }

        if (estimatedLimitPrice == 0) {
            return
                OrderValidation(
                    false,
                    "Invalid limit price",
                    FHE.asEuint64(0),
                    0
                );
        }

        uint256 requiredCollateral = _calculateRequiredCollateral(
            positionType,
            estimatedQuantity,
            estimatedStrikePrice,
            underlying
        );

        if (estimatedCollateral < requiredCollateral) {
            return
                OrderValidation(
                    false,
                    "Insufficient collateral",
                    FHE.asEuint64(SafeCast.toUint64(requiredCollateral)),
                    0
                );
        }

        return
            OrderValidation(
                true,
                "",
                FHE.asEuint64(SafeCast.toUint64(requiredCollateral)),
                200000
            );
    }

    function _calculateRequiredCollateral(
        AscendaDerivativesEngine.PositionType positionType,
        uint256 quantity,
        uint256 strikePrice,
        string memory underlying
    ) internal view returns (uint256) {
        uint256 currentPrice = derivativesEngine
            .oracle()
            .getPrice(underlying)
            .price;

        if (positionType == AscendaDerivativesEngine.PositionType.CALL) {
            return (quantity * strikePrice * 20) / 100;
        } else if (positionType == AscendaDerivativesEngine.PositionType.PUT) {
            return quantity * strikePrice;
        } else {
            return (quantity * currentPrice * 10) / 100;
        }
    }

    function _createLimitOrder(uint256 orderId) internal returns (bytes32) {
        ConfidentialOrder memory order = orders[orderId];

        ILimitOrderProtocol.Order memory limitOrder = ILimitOrderProtocol
            .Order({
                salt: orderId,
                makerAsset: address(confidentialCollateral),
                takerAsset: address(confidentialCollateral),
                maker: order.owner,
                receiver: address(this),
                allowedSender: address(0),
                makingAmount: order.estimatedQuantity,
                takingAmount: order.estimatedLimitPrice,
                offsets: 0,
                interactions: ""
            });

        return limitOrderProtocol.hashOrder(limitOrder);
    }

    function _cancelLimitOrder(bytes32 limitOrderHash) internal {
        uint256 orderId = limitOrderToDerivativeOrder[limitOrderHash];
        if (orderId > 0) {
            ConfidentialOrder memory order = orders[orderId];

            ILimitOrderProtocol.Order memory limitOrder = ILimitOrderProtocol
                .Order({
                    salt: orderId,
                    makerAsset: address(confidentialCollateral),
                    takerAsset: address(confidentialCollateral),
                    maker: order.owner,
                    receiver: address(this),
                    allowedSender: address(0),
                    makingAmount: order.estimatedQuantity,
                    takingAmount: order.estimatedLimitPrice,
                    offsets: 0,
                    interactions: ""
                });

            limitOrderProtocol.cancelOrder(limitOrder);
        }
    }

      function _createDerivativePosition(
        ConfidentialOrder memory order,
        uint256 fillQuantity,
        uint256 executionPrice
    ) internal returns (uint256 positionId) {
        uint256 positionCollateralEstimate = (order.estimatedCollateral * fillQuantity) / order.estimatedQuantity;
        
        euint64 positionCollateral = FHE.asEuint64(SafeCast.toUint64(positionCollateralEstimate));

        positionId = derivativesEngine.openConfidentialPosition(
            order.underlying,
            order.positionType,
            externalEuint64.wrap(euint64.unwrap(FHE.asEuint64(SafeCast.toUint64(fillQuantity)))),
            externalEuint64.wrap(euint64.unwrap(order.strikePrice)),
            externalEuint64.wrap(euint64.unwrap(FHE.asEuint64(SafeCast.toUint64(executionPrice)))),
            order.expiration,
            externalEuint64.wrap(euint64.unwrap(positionCollateral)),
            "",
            "",
            "",
            ""
        );
    }


    function _createStrategyLegOrder(
        string memory underlying,
        AscendaDerivativesEngine.PositionType positionType,
        euint64 quantity,
        euint64 strikePrice,
        euint64 limitPrice,
        uint256 expiration,
        euint64 collateral,
        uint256[4] memory estimatedParams 
    ) internal returns (uint256 orderId) {
        orderId = ++_orderIdCounter;

        orders[orderId] = ConfidentialOrder({
            orderId: orderId,
            owner: msg.sender,
            underlying: underlying,
            positionType: positionType,
            quantity: quantity,
            strikePrice: strikePrice,
            limitPrice: limitPrice,
            stopPrice: FHE.asEuint64(0),
            maxSlippage: FHE.asEuint64(SafeCast.toUint64(MAX_SLIPPAGE_BPS)),
            expiration: expiration,
            orderExpiration: expiration,
            collateralAmount: collateral,
            status: OrderStatus.PENDING,
            createdAt: block.timestamp,
            lastUpdated: block.timestamp,
            limitOrderHash: bytes32(0),
            isStopOrder: false,
            executedQuantity: 0,
            estimatedQuantity: estimatedParams[0],
            estimatedStrikePrice: estimatedParams[1],
            estimatedLimitPrice: estimatedParams[2],
            estimatedCollateral: estimatedParams[3]
        });

        userOrders[msg.sender].push(orderId);

        confidentialCollateral.authorizedTransfer(
            msg.sender,
            address(this),
            collateral
        );
        userLockedCollateral[msg.sender] = FHE.add(
            userLockedCollateral[msg.sender],
            collateral
        );
        userEstimatedLockedCollateral[msg.sender] += estimatedParams[3];

        FHE.allow(quantity, msg.sender);
        FHE.allow(strikePrice, msg.sender);
        FHE.allow(limitPrice, msg.sender);
        FHE.allow(collateral, msg.sender);
    }

    function _isValidStrategyType(
        StrategyType strategyType,
        uint256 numLegs
    ) internal pure returns (bool) {
        if (
            strategyType == StrategyType.BULL_CALL_SPREAD ||
            strategyType == StrategyType.BEAR_PUT_SPREAD ||
            strategyType == StrategyType.BULL_PUT_SPREAD ||
            strategyType == StrategyType.BEAR_CALL_SPREAD
        ) {
            return numLegs == 2;
        } else if (strategyType == StrategyType.IRON_CONDOR) {
            return numLegs == 4;
        } else if (
            strategyType == StrategyType.IRON_BUTTERFLY ||
            strategyType == StrategyType.STRADDLE ||
            strategyType == StrategyType.STRANGLE
        ) {
            return numLegs == 2 || numLegs == 3;
        } else if (
            strategyType == StrategyType.COVERED_CALL ||
            strategyType == StrategyType.PROTECTIVE_PUT ||
            strategyType == StrategyType.COLLAR
        ) {
            return numLegs >= 2 && numLegs <= 3;
        }

        return false;
    }

    function _getPositionTypeForLeg(
        StrategyType strategyType,
        uint256 legIndex
    ) internal pure returns (AscendaDerivativesEngine.PositionType) {
        if (strategyType == StrategyType.BULL_CALL_SPREAD) {
            return AscendaDerivativesEngine.PositionType.CALL;
        } else if (strategyType == StrategyType.BEAR_PUT_SPREAD) {
            return AscendaDerivativesEngine.PositionType.PUT;
        } else if (strategyType == StrategyType.IRON_CONDOR) {
            return
                legIndex < 2
                    ? AscendaDerivativesEngine.PositionType.PUT
                    : AscendaDerivativesEngine.PositionType.CALL;
        } else if (strategyType == StrategyType.STRADDLE) {
            return
                legIndex == 0
                    ? AscendaDerivativesEngine.PositionType.CALL
                    : AscendaDerivativesEngine.PositionType.PUT;
        }

        return AscendaDerivativesEngine.PositionType.CALL;
    }

    function _validateStrategyLogic(
        StrategyType strategyType,
        uint256[] memory legOrderIds
    ) internal  returns (bool) {
        if (
            strategyType == StrategyType.BULL_CALL_SPREAD &&
            legOrderIds.length == 2
        ) {
            ConfidentialOrder memory leg1 = orders[legOrderIds[0]];
            ConfidentialOrder memory leg2 = orders[legOrderIds[1]];

            if (
                leg1.positionType !=
                AscendaDerivativesEngine.PositionType.CALL ||
                leg2.positionType != AscendaDerivativesEngine.PositionType.CALL
            ) {
                return false;
            }

            if (
                keccak256(bytes(leg1.underlying)) !=
                keccak256(bytes(leg2.underlying))
            ) {
                return false;
            }

            if (leg1.expiration != leg2.expiration) {
                return false;
            }

            return true;
        }

        return true;
    }

   function _calculateStrategyMetrics(
        uint256[] memory legOrderIds
    )
        internal
        returns (
            euint64 netPremium,
            euint64 maxLoss,
            euint64 maxProfit,
            bool isCredit,
            uint256 estimatedNetPremium,
            uint256 estimatedMaxLoss,
            uint256 estimatedMaxProfit
        )
    {
        netPremium = FHE.asEuint64(0);
        maxLoss = FHE.asEuint64(0);
        maxProfit = FHE.asEuint64(0);
        isCredit = false;
        
        estimatedNetPremium = 0;
        estimatedMaxLoss = 0;
        estimatedMaxProfit = 0;

        for (uint256 i = 0; i < legOrderIds.length; i++) {
            ConfidentialOrder memory leg = orders[legOrderIds[i]];

            maxLoss = FHE.add(maxLoss, leg.collateralAmount);
            netPremium = FHE.add(netPremium, leg.limitPrice);
            
            estimatedMaxLoss += leg.estimatedCollateral;
            estimatedNetPremium += leg.estimatedLimitPrice;
        }

        estimatedMaxProfit = estimatedMaxLoss / 2;
        maxProfit = FHE.mul(maxLoss, FHE.asEuint64(1)); 
    }

   

    function _calculateFee(
        uint256 notionalValue,
        bool isMaker
    ) internal returns (uint256) {
        uint256 feeBps = isMaker ? makerFeeBps : takerFeeBps;
        return (notionalValue * feeBps) / 10000;
    }

    function _updateDailyVolume(uint256 volumeToAdd) internal {
        uint256 currentDay = block.timestamp / 1 days;

        if (currentDay > lastVolumeResetDay) {
            dailyVolume = 0;
            lastVolumeResetDay = currentDay;
        }

        dailyVolume += volumeToAdd;

        if (dailyVolume > maxDailyVolume) {
            emit CircuitBreakerTriggered(
                dailyVolume,
                maxDailyVolume,
                block.timestamp
            );
        }
    }

    function _isCircuitBroken() internal view returns (bool) {
        uint256 currentDay = block.timestamp / 1 days;

        if (currentDay > lastVolumeResetDay) {
            return false;
        }

        return dailyVolume > maxDailyVolume;
    }
}