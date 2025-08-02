// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {FHE, externalEuint64, euint64, ebool} from "@fhevm/solidity/lib/FHE.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/IFusionProtocol.sol";
import "./AscendaConfidentialCollateral.sol";
import "./AscendaDerivativesEngine.sol";

/**
 * @title CrossChainSettlementManager
 * @dev Production-ready cross-chain settlement with atomic swaps and encrypted amounts
 * @notice Handles confidential cross-chain settlements via 1inch Fusion+ integration
 * @custom:security-contact security@ascenda.xyz
 */
contract CrossChainSettlementManager is AccessControl, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;
    using FHE for euint64;
    using FHE for ebool;
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;
     using FHE for *;


    // ==================== CONSTANTS ====================
    
    bytes32 public constant RESOLVER_ROLE = keccak256("RESOLVER_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");
    bytes32 public constant ORACLE_ROLE = keccak256("ORACLE_ROLE");
    
    uint256 public constant MIN_TIMELOCK = 1 hours;
    uint256 public constant MAX_TIMELOCK = 7 days;
    uint256 public constant RESOLVER_BOND_AMOUNT = 10e6; 
    uint256 public constant LIQUIDATION_PENALTY = 500; 
    uint256 public constant MAX_SLIPPAGE_BPS = 300; 
    uint256 public constant EMERGENCY_DELAY = 24 hours;
    
    uint256 public constant ETHEREUM_MAINNET = 1;
    uint256 public constant ARBITRUM_ONE = 42161;
    uint256 public constant ETHEREUM_TESTNET = 5;
    uint256 public constant ETHERLINK_MAINNET = 42793;
    uint256 public constant ETHERLINK_TESTNET = 42794;
    
    
    // ==================== ENUMS ====================
    
    enum SettlementStatus {
        PENDING,
        LOCKED,
        EXECUTED,
        CANCELLED,
        EXPIRED,
        DISPUTED
    }
    
    enum DisputeStatus {
        NONE,
        RAISED,
        INVESTIGATING,
        RESOLVED_FAVOR_USER,
        RESOLVED_FAVOR_RESOLVER
    }
    
    // ==================== STRUCTS ====================
    
    struct ConfidentialSettlement {
        uint256 settlementId;
        address owner;
        address resolver;
        uint256 positionId;
        address sourceToken;
        address destinationToken;
        uint256 sourceChainId;
        uint256 destinationChainId;
        euint64 amount;                
        euint64 resolverBond;           
        bytes32 secretHash;
        bytes32 secret;                
        uint256 timelock;
        uint256 deadline;              
        SettlementStatus status;
        DisputeStatus disputeStatus;
        uint256 createdAt;
        uint256 lockedAt;
        uint256 executedAt;
        euint64 executedAmount;         
        uint256 gasFeeLimit;           
        bool emergencyRefundApproved;
    }
    
    struct AtomicSwapEscrow {
        bytes32 escrowId;
        address initiator;
        address participant;
        address token;
        euint64 amount;                 
        bytes32 secretHash;
        uint256 timelock;
        bool redeemed;
        bool refunded;
        uint256 createdAt;
        euint64 actualAmount;           
    }
    
    struct ResolverInfo {
        address resolver;
        bool isActive;
        uint256 bondAmount;
        uint256 successfulSettlements;
        uint256 failedSettlements;
        uint256 totalVolumeHandled;
        uint256 averageExecutionTime;
        uint256 reputation;            
        uint256 lastActiveTime;
        bool isSlashed;
    }
    
    struct ChainConfig {
        uint256 chainId;
        bool isSupported;
        uint256 minTimelock;
        uint256 maxTimelock;
        uint256 confirmationBlocks;
        address bridgeContract;
        bool isActive;
    }
    
    // ==================== STATE VARIABLES ====================
    
    mapping(uint256 => ConfidentialSettlement) public settlements;
    mapping(bytes32 => AtomicSwapEscrow) public escrows;
    mapping(address => ResolverInfo) public resolvers;
    mapping(uint256 => ChainConfig) public supportedChains;
    mapping(address => uint256[]) public userSettlements;
    mapping(address => bytes32[]) public resolverEscrows;
    mapping(bytes32 => uint256) public secretToSettlement;
    
    mapping(address => uint256) public emergencyRefundRequests;
    mapping(uint256 => bool) public emergencyRefundApproved;
    
    mapping(address => euint64) public resolverEarnings;
    mapping(uint256 => euint64) public chainVolume; 
    mapping(uint256 => uint256) public lastVolumeResetDay;
    
    uint256 private _settlementIdCounter;
    uint256 public totalValueLocked;
    uint256 public totalFeesCollected;
    
    AscendaDerivativesEngine public immutable derivativesEngine;
    AscendaConfidentialCollateral public immutable confidentialCollateral;
    IFusionProtocol public fusionProtocol;
    
    uint256 public protocolFeeBps = 30; 
    uint256 public resolverFeeBps = 20;  
    uint256 public maxDailyVolumePerChain = 50_000_000e6; 
    address public treasury;
    address public insuranceFund;
    
    // ==================== EVENTS ====================
    
    event SettlementInitiated(
        uint256 indexed settlementId,
        address indexed owner,
        uint256 indexed positionId,
        uint256 sourceChainId,
        uint256 destinationChainId,
        bytes32 secretHash
    );
    
    event SettlementLocked(
        uint256 indexed settlementId,
        address indexed resolver,
        bytes32 escrowId,
        uint256 timelock
    );
    
    event SettlementExecuted(
        uint256 indexed settlementId,
        address indexed resolver,
        bytes32 secret,
        uint256 executedAmount
    );
    
    event SettlementCancelled(
        uint256 indexed settlementId,
        address indexed owner,
        string reason
    );
    
    event EscrowCreated(
        bytes32 indexed escrowId,
        address indexed initiator,
        address indexed participant,
        address token,
        bytes32 secretHash
    );
    
    event EscrowRedeemed(
        bytes32 indexed escrowId,
        address indexed redeemer,
        bytes32 secret,
        uint256 amount
    );
    
    event EscrowRefunded(
        bytes32 indexed escrowId,
        address indexed initiator,
        uint256 amount
    );
    
    event ResolverRegistered(
        address indexed resolver,
        uint256 bondAmount
    );
    
    event ResolverSlashed(
        address indexed resolver,
        uint256 slashedAmount,
        string reason
    );
    
    event DisputeRaised(
        uint256 indexed settlementId,
        address indexed complainant,
        string reason
    );
    
    event DisputeResolved(
        uint256 indexed settlementId,
        DisputeStatus resolution,
        address indexed winner
    );
    
    event ChainConfigUpdated(
        uint256 indexed chainId,
        bool isSupported,
        address bridgeContract
    );
    
    event EmergencyRefundRequested(
        uint256 indexed settlementId,
        address indexed user,
        uint256 requestTime
    );
    
    event ProtocolParametersUpdated(
        uint256 protocolFeeBps,
        uint256 resolverFeeBps,
        uint256 maxDailyVolumePerChain
    );
    
    // ==================== MODIFIERS ====================
    
    modifier onlyValidSettlement(uint256 settlementId) {
        require(settlementId > 0 && settlementId <= _settlementIdCounter, "Invalid settlement ID");
        require(settlements[settlementId].owner != address(0), "Settlement does not exist");
        _;
    }
    
    modifier onlySettlementOwner(uint256 settlementId) {
        require(settlements[settlementId].owner == msg.sender, "Not settlement owner");
        _;
    }
    
    modifier onlyActiveResolver() {
        require(resolvers[msg.sender].isActive, "Not active resolver");
        require(!resolvers[msg.sender].isSlashed, "Resolver is slashed");
        _;
    }
    
    modifier onlySupportedChain(uint256 chainId) {
        require(supportedChains[chainId].isSupported, "Chain not supported");
        require(supportedChains[chainId].isActive, "Chain not active");
        _;
    }
    
    modifier volumeCheck(uint256 chainId, uint256 amount) {
        _updateChainVolume(chainId, amount);
        require(
            FHE.decrypt(chainVolume[chainId]) <= maxDailyVolumePerChain,
            "Daily volume limit exceeded for chain"
        );
        _;
    }
    
    modifier deadlineCheck(uint256 settlementId) {
        ConfidentialSettlement storage settlement = settlements[settlementId];
        require(block.timestamp <= settlement.deadline, "Settlement deadline exceeded");
        _;
    }
    
    // ==================== CONSTRUCTOR ====================
    
    constructor(
        address _derivativesEngine,
        address _confidentialCollateral,
        address _fusionProtocol,
        address _treasury,
        address _insuranceFund,
        address _admin
    ) {
        require(_derivativesEngine != address(0), "Invalid derivatives engine");
        require(_confidentialCollateral != address(0), "Invalid collateral");
        require(_treasury != address(0), "Invalid treasury");
        require(_insuranceFund != address(0), "Invalid insurance fund");
        require(_admin != address(0), "Invalid admin");
        
        derivativesEngine = AscendaDerivativesEngine(_derivativesEngine);
        confidentialCollateral = AscendaConfidentialCollateral(_confidentialCollateral);
        fusionProtocol = IFusionProtocol(_fusionProtocol);
        treasury = _treasury;
        insuranceFund = _insuranceFund;
        
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(OPERATOR_ROLE, _admin);
        _grantRole(EMERGENCY_ROLE, _admin);
        
        _initializeSupportedChains();
    }
    
    // ==================== EXTERNAL FUNCTIONS ====================
    
    /**
     * @notice Register as a resolver with required bond
     * @param bondAmount Amount of USDC to bond (must be >= RESOLVER_BOND_AMOUNT)
     */
    function registerResolver(uint256 bondAmount) external nonReentrant whenNotPaused {
        require(bondAmount >= RESOLVER_BOND_AMOUNT, "Insufficient bond amount");
        require(!resolvers[msg.sender].isActive, "Already registered");
        
        confidentialCollateral.authorizedTransfer(
            msg.sender,
            address(this),
            FHE.asEuint64(bondAmount)
        );
        
        resolvers[msg.sender] = ResolverInfo({
            resolver: msg.sender,
            isActive: true,
            bondAmount: bondAmount,
            successfulSettlements: 0,
            failedSettlements: 0,
            totalVolumeHandled: 0,
            averageExecutionTime: 0,
            reputation: 500, 
            lastActiveTime: block.timestamp,
            isSlashed: false
        });
        
        _grantRole(RESOLVER_ROLE, msg.sender);
        
        emit ResolverRegistered(msg.sender, bondAmount);
    }
    
    /**
     * @notice Initiate cross-chain settlement for a position
     * @param positionId ID of the position to settle
     * @param destinationToken Token address on destination chain
     * @param destinationChainId Target chain ID
     * @param encryptedAmount Encrypted settlement amount
     * @param secretHash Hash of the secret for atomic swap
     * @param timelock Time until automatic refund
     * @param gasFeeLimit Maximum gas fee resolver can charge
     * @param amountProof Proof for encrypted amount
     */
    function initiateSettlement(
        uint256 positionId,
        address destinationToken,
        uint256 destinationChainId,
        externalEuint64  encryptedAmount,
        bytes32 secretHash,
        uint256 timelock,
        uint256 gasFeeLimit,
        bytes calldata amountProof
    ) external 
        nonReentrant 
        whenNotPaused 
        onlySupportedChain(destinationChainId) 
        returns (uint256 settlementId) 
    {
        require(positionId > 0, "Invalid position ID");
        require(destinationToken != address(0), "Invalid destination token");
        require(destinationChainId != block.chainid, "Same chain settlement");
        require(secretHash != bytes32(0), "Invalid secret hash");
        require(timelock >= MIN_TIMELOCK && timelock <= MAX_TIMELOCK, "Invalid timelock");
        require(gasFeeLimit > 0, "Invalid gas fee limit");
        
        // Verify position ownership
        // Note: This would need integration with the derivatives engine to verify ownership
        // For now, we'll assume the caller owns the position
        
        euint64 amount = FHE.fromExternal(encryptedAmount, amountProof);
        
        require(FHE.decrypt(FHE.gt(amount, FHE.asEuint64(0))), "Invalid amount");
        
        uint256 decryptedAmount = FHE.decrypt(amount);
        _updateChainVolume(destinationChainId, decryptedAmount);
        require(
            FHE.decrypt(chainVolume[destinationChainId]) <= maxDailyVolumePerChain,
            "Daily volume limit exceeded"
        );
        
        settlementId = ++_settlementIdCounter;
        uint256 deadline = block.timestamp + timelock;
        
        settlements[settlementId] = ConfidentialSettlement({
            settlementId: settlementId,
            owner: msg.sender,
            resolver: address(0),
            positionId: positionId,
            sourceToken: address(confidentialCollateral),
            destinationToken: destinationToken,
            sourceChainId: block.chainid,
            destinationChainId: destinationChainId,
            amount: amount,
            resolverBond: FHE.asEuint64(0),
            secretHash: secretHash,
            secret: bytes32(0),
            timelock: timelock,
            deadline: deadline,
            status: SettlementStatus.PENDING,
            disputeStatus: DisputeStatus.NONE,
            createdAt: block.timestamp,
            lockedAt: 0,
            executedAt: 0,
            executedAmount: FHE.asEuint64(0),
            gasFeeLimit: gasFeeLimit,
            emergencyRefundApproved: false
        });
        
        userSettlements[msg.sender].push(settlementId);
        
        confidentialCollateral.authorizedTransfer(msg.sender, address(this), amount);
        totalValueLocked = totalValueLocked.add(decryptedAmount);
        
        FHE.allow(amount, msg.sender);
        
        emit SettlementInitiated(
            settlementId,
            msg.sender,
            positionId,
            block.chainid,
            destinationChainId,
            secretHash
        );
    }
    
    /**
     * @notice Lock settlement by depositing resolver bond and creating escrow
     * @param settlementId Settlement to lock
     * @param encryptedBond Encrypted bond amount
     * @param bondProof Proof for encrypted bond amount
     */
    function lockSettlement(
        uint256 settlementId,
        externalEuint64  encryptedBond,
        bytes calldata bondProof
    ) external 
        nonReentrant 
        whenNotPaused 
        onlyActiveResolver 
        onlyValidSettlement(settlementId) 
        deadlineCheck(settlementId) 
        returns (bytes32 escrowId) 
    {
        ConfidentialSettlement storage settlement = settlements[settlementId];
        require(settlement.status == SettlementStatus.PENDING, "Settlement not available");
        require(settlement.resolver == address(0), "Settlement already locked");
        
        euint64 bond = FHE.fromExternal(encryptedBond, bondProof);
        
        uint256 requiredBond = _calculateRequiredBond(settlement.amount);
        require(FHE.decrypt(FHE.gte(bond, FHE.asEuint64(requiredBond))), "Insufficient bond");
        
        confidentialCollateral.authorizedTransfer(msg.sender, address(this), bond);
        
        settlement.resolver = msg.sender;
        settlement.resolverBond = bond;
        settlement.status = SettlementStatus.LOCKED;
        settlement.lockedAt = block.timestamp;
        
        escrowId = _createAtomicSwapEscrow(
            msg.sender,
            settlement.owner,
            settlement.destinationToken,
            settlement.amount,
            settlement.secretHash,
            settlement.timelock
        );
        
        resolvers[msg.sender].lastActiveTime = block.timestamp;
        
        emit SettlementLocked(settlementId, msg.sender, escrowId, settlement.timelock);
    }
    
    /**
     * @notice Execute settlement by revealing secret
     * @param settlementId Settlement to execute
     * @param secret The secret that hashes to secretHash
     * @param destinationTxHash Transaction hash on destination chain (for verification)
     */
    function executeSettlement(
        uint256 settlementId,
        bytes32 secret,
        bytes32 destinationTxHash
    ) external 
        nonReentrant 
        whenNotPaused 
        onlyValidSettlement(settlementId) 
        deadlineCheck(settlementId) 
    {
        ConfidentialSettlement storage settlement = settlements[settlementId];
        require(settlement.status == SettlementStatus.LOCKED, "Settlement not locked");
        require(settlement.resolver == msg.sender, "Not the resolver");
        require(keccak256(abi.encodePacked(secret)) == settlement.secretHash, "Invalid secret");
        require(destinationTxHash != bytes32(0), "Invalid destination tx hash");
        
        require(secretToSettlement[secret] == 0, "Secret already used");
        
        settlement.secret = secret;
        settlement.status = SettlementStatus.EXECUTED;
        settlement.executedAt = block.timestamp;
        settlement.executedAmount = settlement.amount; 
        
        secretToSettlement[secret] = settlementId;
        
        (uint256 protocolFee, uint256 resolverFee) = _calculateFees(settlement.amount);
        
        euint64 userAmount = FHE.sub(settlement.amount, FHE.asEuint64(protocolFee + resolverFee));
        confidentialCollateral.authorizedTransfer(address(this), settlement.owner, userAmount);
        
        if (protocolFee > 0) {
            confidentialCollateral.authorizedTransfer(address(this), treasury, FHE.asEuint64(protocolFee));
        }
        if (resolverFee > 0) {
            resolverEarnings[msg.sender] = FHE.add(resolverEarnings[msg.sender], FHE.asEuint64(resolverFee));
        }
        
        confidentialCollateral.authorizedTransfer(address(this), msg.sender, settlement.resolverBond);
        
        ResolverInfo storage resolverInfo = resolvers[msg.sender];
        resolverInfo.successfulSettlements++;
        resolverInfo.totalVolumeHandled += FHE.decrypt(settlement.amount);
        
        uint256 executionTime = block.timestamp - settlement.lockedAt;
        resolverInfo.averageExecutionTime = 
            (resolverInfo.averageExecutionTime + executionTime) / 2;
        
        if (executionTime < 1 hours) {
            resolverInfo.reputation = _min(1000, resolverInfo.reputation + 10);
        }
        
        totalValueLocked = totalValueLocked.sub(FHE.decrypt(settlement.amount));
        totalFeesCollected = totalFeesCollected.add(protocolFee);
        
        emit SettlementExecuted(settlementId, msg.sender, secret, FHE.decrypt(settlement.executedAmount));
    }
    
    /**
     * @notice Cancel settlement (owner or emergency role)
     * @param settlementId Settlement to cancel
     * @param reason Reason for cancellation
     */
    function cancelSettlement(
        uint256 settlementId,
        string calldata reason
    ) external 
        nonReentrant 
        onlyValidSettlement(settlementId) 
    {
        ConfidentialSettlement storage settlement = settlements[settlementId];
        
        // Authorization checks
        bool isOwner = msg.sender == settlement.owner;
        bool isEmergency = hasRole(EMERGENCY_ROLE, msg.sender);
        bool isExpired = block.timestamp > settlement.deadline;
        
        require(
            isOwner || isEmergency || isExpired,
            "Not authorized to cancel"
        );
        
        require(
            settlement.status == SettlementStatus.PENDING || 
            settlement.status == SettlementStatus.LOCKED,
            "Settlement cannot be cancelled"
        );
        
        settlement.status = SettlementStatus.CANCELLED;
        
        confidentialCollateral.authorizedTransfer(address(this), settlement.owner, settlement.amount);
        totalValueLocked = totalValueLocked.sub(FHE.decrypt(settlement.amount));
        
        if (settlement.status == SettlementStatus.LOCKED && settlement.resolver != address(0)) {
            if (isExpired && !isEmergency) {
                _slashResolver(settlement.resolver, settlement.resolverBond, "Settlement timeout");
            } else {
                confidentialCollateral.authorizedTransfer(
                    address(this), 
                    settlement.resolver, 
                    settlement.resolverBond
                );
            }
            
            resolvers[settlement.resolver].failedSettlements++;
        }
        
        emit SettlementCancelled(settlementId, settlement.owner, reason);
    }
    
    /**
     * @notice Raise a dispute for a settlement
     * @param settlementId Settlement ID to dispute
     * @param reason Reason for the dispute
     */
    function raiseDispute(
        uint256 settlementId,
        string calldata reason
    ) external 
        nonReentrant 
        onlyValidSettlement(settlementId) 
    {
        ConfidentialSettlement storage settlement = settlements[settlementId];
        require(
            msg.sender == settlement.owner || msg.sender == settlement.resolver,
            "Not authorized to raise dispute"
        );
        require(settlement.disputeStatus == DisputeStatus.NONE, "Dispute already raised");
        require(
            settlement.status == SettlementStatus.EXECUTED || 
            settlement.status == SettlementStatus.LOCKED,
            "Invalid settlement status for dispute"
        );
        
        settlement.disputeStatus = DisputeStatus.RAISED;
        
        emit DisputeRaised(settlementId, msg.sender, reason);
    }
    
    /**
     * @notice Request emergency refund (starts delay timer)
     * @param settlementId Settlement ID for emergency refund
     */
    function requestEmergencyRefund(
        uint256 settlementId
    ) external 
        nonReentrant 
        onlyValidSettlement(settlementId) 
        onlySettlementOwner(settlementId) 
    {
        require(emergencyRefundRequests[msg.sender] == 0, "Request already pending");
        require(!emergencyRefundApproved[settlementId], "Already approved");
        
        ConfidentialSettlement storage settlement = settlements[settlementId];
        require(
            settlement.status == SettlementStatus.LOCKED || 
            settlement.status == SettlementStatus.PENDING,
            "Invalid status for emergency refund"
        );
        
        emergencyRefundRequests[msg.sender] = block.timestamp;
        
        emit EmergencyRefundRequested(settlementId, msg.sender, block.timestamp);
    }
    
    /**
     * @notice Execute emergency refund after delay
     * @param settlementId Settlement to refund
     */
    function executeEmergencyRefund(
        uint256 settlementId
    ) external 
        nonReentrant 
        onlyValidSettlement(settlementId) 
        onlySettlementOwner(settlementId) 
    {
        require(emergencyRefundRequests[msg.sender] > 0, "No refund request");
        require(
            block.timestamp >= emergencyRefundRequests[msg.sender] + EMERGENCY_DELAY,
            "Emergency delay not met"
        );
        require(emergencyRefundApproved[settlementId], "Refund not approved");
        
        ConfidentialSettlement storage settlement = settlements[settlementId];
        settlement.status = SettlementStatus.CANCELLED;
        settlement.emergencyRefundApproved = true;
        
        emergencyRefundRequests[msg.sender] = 0;
        
        confidentialCollateral.authorizedTransfer(address(this), msg.sender, settlement.amount);
        totalValueLocked = totalValueLocked.sub(FHE.decrypt(settlement.amount));
        
        if (settlement.resolver != address(0)) {
            _slashResolver(settlement.resolver, settlement.resolverBond, "Emergency refund executed");
        }
    }
    
    // ==================== ADMIN FUNCTIONS ====================
    
    function updateProtocolParameters(
        uint256 _protocolFeeBps,
        uint256 _resolverFeeBps,
        uint256 _maxDailyVolumePerChain
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_protocolFeeBps <= 100, "Protocol fee too high");
        require(_resolverFeeBps <= 100, "Resolver fee too high");
        require(_maxDailyVolumePerChain > 0, "Invalid volume limit");
        
        protocolFeeBps = _protocolFeeBps;
        resolverFeeBps = _resolverFeeBps;
        maxDailyVolumePerChain = _maxDailyVolumePerChain;
        
        emit ProtocolParametersUpdated(_protocolFeeBps, _resolverFeeBps, _maxDailyVolumePerChain);
    }
    
    function updateChainConfig(
        uint256 chainId,
        bool isSupported,
        uint256 minTimelock,
        uint256 maxTimelock,
        uint256 confirmationBlocks,
        address bridgeContract,
        bool isActive
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(chainId > 0, "Invalid chain ID");
        require(minTimelock >= MIN_TIMELOCK, "Timelock too short");
        require(maxTimelock <= MAX_TIMELOCK, "Timelock too long");
        
        supportedChains[chainId] = ChainConfig({
            chainId: chainId,
            isSupported: isSupported,
            minTimelock: minTimelock,
            maxTimelock: maxTimelock,
            confirmationBlocks: confirmationBlocks,
            bridgeContract: bridgeContract,
            isActive: isActive
        });
        
        emit ChainConfigUpdated(chainId, isSupported, bridgeContract);
    }
    
    function setFusionProtocol(address _fusionProtocol) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_fusionProtocol != address(0), "Invalid address");
        fusionProtocol = IFusionProtocol(_fusionProtocol);
    }
    
    function approveEmergencyRefund(uint256 settlementId) external onlyRole(EMERGENCY_ROLE) {
        require(settlements[settlementId].owner != address(0), "Settlement does not exist");
        emergencyRefundApproved[settlementId] = true;
    }
    
    function slashResolver(
        address resolver,
        uint256 amount,
        string calldata reason
    ) external onlyRole(EMERGENCY_ROLE) {
        require(resolvers[resolver].isActive, "Resolver not active");
        require(amount <= resolvers[resolver].bondAmount, "Amount exceeds bond");
        
        _slashResolver(resolver, FHE.asEuint64(amount), reason);
    }
    
    function resolveDispute(
        uint256 settlementId,
        DisputeStatus resolution
    ) external onlyRole(ORACLE_ROLE) onlyValidSettlement(settlementId) {
        ConfidentialSettlement storage settlement = settlements[settlementId];
        require(settlement.disputeStatus == DisputeStatus.RAISED, "No active dispute");
        require(
            resolution == DisputeStatus.RESOLVED_FAVOR_USER || 
            resolution == DisputeStatus.RESOLVED_FAVOR_RESOLVER,
            "Invalid resolution"
        );
        
        settlement.disputeStatus = resolution;
        
        address winner = resolution == DisputeStatus.RESOLVED_FAVOR_USER ? 
            settlement.owner : settlement.resolver;
        
        emit DisputeResolved(settlementId, resolution, winner);
    }
    
    function pauseContract() external onlyRole(EMERGENCY_ROLE) {
        _pause();
    }
    
    function unpauseContract() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }
    
    // ==================== VIEW FUNCTIONS ====================
    
    function getSettlement(uint256 settlementId) external view returns (ConfidentialSettlement memory) {
        return settlements[settlementId];
    }
    
    function getEscrow(bytes32 escrowId) external view returns (AtomicSwapEscrow memory) {
        return escrows[escrowId];
    }
    
    function getResolver(address resolver) external view returns (ResolverInfo memory) {
        return resolvers[resolver];
    }
    
    function getUserSettlements(address user) external view returns (uint256[] memory) {
        return userSettlements[user];
    }
    
    function getResolverEscrows(address resolver) external view returns (bytes32[] memory) {
        return resolverEscrows[resolver];
    }
    
    function getSettlementCount() external view returns (uint256) {
        return _settlementIdCounter;
    }
    
    function getChainConfig(uint256 chainId) external view returns (ChainConfig memory) {
        return supportedChains[chainId];
    }
    
    function isChainSupported(uint256 chainId) external view returns (bool) {
        return supportedChains[chainId].isSupported && supportedChains[chainId].isActive;
    }
    
    function getResolverEarnings(address resolver) external view returns (euint64) {
        euint64 earnings = resolverEarnings[resolver];
        if (msg.sender == resolver) {
            FHE.allow(earnings, resolver);
        }
        return earnings;
    }
    
    // ==================== INTERNAL FUNCTIONS ====================
    
    function _createAtomicSwapEscrow(
        address initiator,
        address participant,
        address token,
        euint64 amount,
        bytes32 secretHash,
        uint256 timelock
    ) internal returns (bytes32 escrowId) {
        escrowId = keccak256(
            abi.encodePacked(
                initiator,
                participant,
                token,
                euint64.unwrap(amount),
                secretHash,
                block.timestamp
            )
        );
        
        (uint256 protocolFee, uint256 resolverFee) = _calculateFees(amount);
        euint64 actualAmount = FHE.sub(amount, FHE.asEuint64(protocolFee + resolverFee));
        
        escrows[escrowId] = AtomicSwapEscrow({
            escrowId: escrowId,
            initiator: initiator,
            participant: participant,
            token: token,
            amount: amount,
            secretHash: secretHash,
            timelock: block.timestamp + timelock,
            redeemed: false,
            refunded: false,
            createdAt: block.timestamp,
            actualAmount: actualAmount
        });
        
        resolverEscrows[initiator].push(escrowId);
        
        emit EscrowCreated(escrowId, initiator, participant, token, secretHash);
    }
    
    function _calculateRequiredBond(euint64 settlementAmount) internal pure returns (uint256) {
        uint256 amount = FHE.decrypt(settlementAmount);
        uint256 calculatedBond = amount.mul(10).div(100);
        return _max(calculatedBond, RESOLVER_BOND_AMOUNT);
    }
    
    function _calculateFees(euint64 amount) internal view returns (uint256 protocolFee, uint256 resolverFee) {
        uint256 amountDecrypted = FHE.decrypt(amount);
        protocolFee = amountDecrypted.mul(protocolFeeBps).div(10000);
        resolverFee = amountDecrypted.mul(resolverFeeBps).div(10000);
    }
    
    function _slashResolver(address resolver, euint64 amount, string memory reason) internal {
        ResolverInfo storage resolverInfo = resolvers[resolver];
        require(resolverInfo.isActive, "Resolver not active");
        
        uint256 slashAmount = FHE.decrypt(amount);
        require(slashAmount <= resolverInfo.bondAmount, "Slash amount exceeds bond");
        
        confidentialCollateral.authorizedTransfer(address(this), insuranceFund, amount);
        
        resolverInfo.bondAmount = resolverInfo.bondAmount.sub(slashAmount);
        resolverInfo.isSlashed = true;
        resolverInfo.reputation = resolverInfo.reputation > 100 ? 
            resolverInfo.reputation - 100 : 0;
        
        if (resolverInfo.bondAmount < RESOLVER_BOND_AMOUNT) {
            resolverInfo.isActive = false;
            _revokeRole(RESOLVER_ROLE, resolver);
        }
        
        emit ResolverSlashed(resolver, slashAmount, reason);
    }
    
    function _updateChainVolume(uint256 chainId, uint256 amount) internal {
        uint256 currentDay = block.timestamp / 1 days;
        
        if (currentDay > lastVolumeResetDay[chainId]) {
            chainVolume[chainId] = FHE.asEuint64(0);
            lastVolumeResetDay[chainId] = currentDay;
        }
        
        chainVolume[chainId] = FHE.add(chainVolume[chainId], FHE.asEuint64(amount));
    }
    
    function _initializeSupportedChains() internal {
        supportedChains[ETHEREUM_MAINNET] = ChainConfig({
            chainId: ETHEREUM_MAINNET,
            isSupported: true,
            minTimelock: 2 hours,
            maxTimelock: 3 days,
            confirmationBlocks: 12,
            bridgeContract: address(0), 
            isActive: true
        });
        
        supportedChains[ETHERLINK_MAINNET] = ChainConfig({
            chainId: ETHERLINK_MAINNET,
            isSupported: true,
            minTimelock: 1 hours,
            maxTimelock: 2 days,
            confirmationBlocks: 1,
            bridgeContract: address(0),
            isActive: true
        });
        
        supportedChains[ETHERLINK_TESTNET] = ChainConfig({
            chainId: ETHERLINK_TESTNET,
            isSupported: true,
            minTimelock: 1 hours,
            maxTimelock: 2 days,
            confirmationBlocks: 1,
            bridgeContract: address(0),
            isActive: true
        });

        supportedChains[ETHEREUM_TESTNET] = ChainConfig({
            chainId: ETHEREUM_TESTNET,
            isSupported: true,
            minTimelock: 1 hours,
            maxTimelock: 2 days,
            confirmationBlocks: 1,
            bridgeContract: address(0),
            isActive: true
        });
    }
    
    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
    
    function _max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }
}