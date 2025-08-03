// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {FHE, euint64} from "@fhevm/solidity/lib/FHE.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {ConfidentialFungibleToken} from "@openzeppelin/confidential-contracts/token/ConfidentialFungibleToken.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/**
 * @title AscendaConfidentialCollateral
 * @dev Direct implementation of ConfidentialFungibleToken with ERC20 wrapping logic for USDC/USDT collateral.
 */
contract AscendaConfidentialCollateral is
    ReentrancyGuard,
    Pausable,
    Ownable,
    ConfidentialFungibleToken
{
    using FHE for *;
    using SafeERC20 for IERC20;

    IERC20 private immutable _underlying;
    uint8 private immutable _underlyingDecimals;
    uint8 private immutable _decimals;
    uint256 private immutable _rate;

    mapping(address => bool) public authorizedContracts;
    mapping(address => mapping(address => bool)) public allowances;
    
    mapping(uint256 => UnwrapRequest) private _unwrapRequests;
    
    struct UnwrapRequest {
        address from;
        address to;
        uint64 amount;
        bool exists;
    }

    uint256 public constant MAX_SUPPLY = type(uint64).max;
    uint256 public constant MIN_DEPOSIT_AMOUNT = 10; 
    
    event ContractAuthorized(address indexed contractAddress, bool authorized);
    event ConfidentialDeposit(address indexed user, euint64 amount);
    event ConfidentialWithdrawal(address indexed from, address indexed to, euint64 amount);
    event AllowanceSet(address indexed owner, address indexed spender, bool allowed);
    event UnwrapRequested(uint256 indexed requestId, address indexed from, address indexed to, uint64 amount);
    event UnwrapFinalized(uint256 indexed requestId, address indexed to, uint256 amount);

    modifier onlyAuthorized() {
        require(
            authorizedContracts[msg.sender] || msg.sender == owner(),
            "ACC: Not authorized"
        );
        _;
    }

    modifier validAddress(address addr) {
        require(addr != address(0), "ACC: Invalid address");
        _;
    }

    modifier sufficientAmount(uint256 amount) {
        require(amount >= MIN_DEPOSIT_AMOUNT, "ACC: Amount too small");
        _;
    }

    constructor(
        IERC20 underlying_,
        string memory name_,
        string memory symbol_,
        string memory tokenURI_
    ) ConfidentialFungibleToken(name_, symbol_, tokenURI_) Ownable(msg.sender) {
        require(address(underlying_) != address(0), "ACC: Invalid underlying token");
        
        _underlying = underlying_;
        _underlyingDecimals = _tryGetAssetDecimals(underlying_);
        _decimals = 6; 
        
        if (_underlyingDecimals >= _decimals) {
            _rate = 10 ** (_underlyingDecimals - _decimals);
        } else {
            _rate = 1;
        }
        
        require(_rate > 0, "ACC: Invalid rate calculation");
    }

    /// @notice Underlying ERC20 token.
    function underlying() public view returns (IERC20) {
        return _underlying;
    }

    /// @notice Conversion rate between underlying token and confidential token.
    function rate() public view returns (uint256) {
        return _rate;
    }

    
    /**
     * @notice Authorize contracts to interact with confidential balances.
     * @param contractAddress The contract to authorize/deauthorize
     * @param authorized Whether to authorize or revoke authorization
     */
    function setContractAuthorization(address contractAddress, bool authorized)
        external
        validAddress(contractAddress)
    {
        require(contractAddress != address(this), "ACC: Cannot authorize self");
        authorizedContracts[contractAddress] = authorized;
        emit ContractAuthorized(contractAddress, authorized);
    }

    /**
     * @notice Set allowance for authorized contracts to spend user's confidential tokens
     * @param spender The address to authorize
     * @param allowed Whether to allow or revoke permission
     */
    function setAllowance(address spender, bool allowed) 
        external 
        validAddress(spender) 
    {
        allowances[msg.sender][spender] = allowed;
        emit AllowanceSet(msg.sender, spender, allowed);
    }

    /**
     * @notice Deposit public tokens and mint confidential tokens.
     * @param to The recipient of the confidential tokens
     * @param amount The amount of underlying tokens to deposit
     */
    function confidentialDeposit(address to, uint256 amount)
        external
        whenNotPaused
        nonReentrant
        validAddress(to)
        sufficientAmount(amount)
    {
        uint256 transferable = amount - (amount % _rate);
        require(transferable > 0, "ACC: Insufficient amount after scaling");

        uint64 confidentialAmount = SafeCast.toUint64(transferable / _rate);
        require(confidentialAmount > 0, "ACC: Confidential amount too small");

        _underlying.safeTransferFrom(msg.sender, address(this), transferable);

        euint64 encryptedAmount = FHE.asEuint64(confidentialAmount);
        _mint(to, encryptedAmount);

        emit ConfidentialDeposit(to, encryptedAmount);
    }

    /**
     * @notice Withdraw confidential tokens and receive public tokens
     * @param from The address to withdraw from
     * @param to The recipient of the public tokens
     * @param amount The confidential amount to withdraw
     */
    function confidentialWithdrawFrom(address from, address to, euint64 amount)
        external
        onlyAuthorized
        whenNotPaused
        nonReentrant
        validAddress(to)
    {
        if (msg.sender != from && msg.sender != owner()) {
            require(
                allowances[from][msg.sender], 
                "ACC: Not authorized to withdraw from this address"
            );
        }

        require(
            FHE.isAllowed(amount, address(this)),
            "ACC: Contract not authorized for amount"
        );

        euint64 burntAmount = _burn(from, amount);

        bytes32[] memory cts = new bytes32[](1);
        cts[0] = euint64.unwrap(burntAmount);

        uint256 requestId = FHE.requestDecryption(cts, this.finalizeUnwrap.selector);
        
        _unwrapRequests[requestId] = UnwrapRequest({
            from: from,
            to: to,
            amount: 0, 
            exists: true
        });

        emit ConfidentialWithdrawal(from, to, burntAmount);
    }

    /**
     * @notice Transfer confidential tokens between addresses with authorization
     * @param from The sender address
     * @param to The recipient address  
     * @param amount The confidential amount to transfer
     * @return The transferred amount
     */
    function authorizedTransfer(address from, address to, euint64 amount)
        external
        onlyAuthorized
        whenNotPaused
        validAddress(to)
        returns (euint64)
    {
        if (msg.sender != from && msg.sender != owner()) {
            require(
                allowances[from][msg.sender],
                "ACC: Not authorized to transfer from this address"
            );
        }

        require(
            FHE.isAllowed(amount, address(this)),
            "ACC: Contract not authorized for amount"
        );

        return _transfer(from, to, amount);
    }

    /**
     * @dev Called by the fhEVM gateway with the decrypted amount for a request id.
     * Transfers out public tokens to the specified recipient.
     * @param requestId The decryption request identifier
     * @param amount The decrypted amount
     * @param signatures The gateway signatures for verification
     */
    function finalizeUnwrap(uint256 requestId, uint64 amount, bytes[] calldata signatures)
        external
        nonReentrant
    {
        FHE.checkSignatures(requestId, signatures);
        
        UnwrapRequest storage request = _unwrapRequests[requestId];
        require(request.exists, "ACC: Invalid unwrap request");
        
        address to = request.to;
        delete _unwrapRequests[requestId];

        require(amount > 0, "ACC: Invalid decrypted amount");
        
        uint256 publicAmount;
        unchecked {
            publicAmount = uint256(amount) * _rate;
        }
        
        require(
            _underlying.balanceOf(address(this)) >= publicAmount,
            "ACC: Insufficient contract balance"
        );

        _underlying.safeTransfer(to, publicAmount);
        
        emit UnwrapFinalized(requestId, to, publicAmount);
    }

    /**
     * @notice Emergency withdrawal function for owner (only in paused state)
     * @param token The token to withdraw
     * @param to The recipient address
     * @param amount The amount to withdraw
     */
    function emergencyWithdraw(IERC20 token, address to, uint256 amount)
        external
        onlyOwner
        whenPaused
        validAddress(to)
    {
        require(amount > 0, "ACC: Amount must be greater than 0");
        token.safeTransfer(to, amount);
    }

    /**
     * @notice Pause the contract (onlyOwner).
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpause the contract (onlyOwner).
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Get the underlying token balance of this contract
     * @return The balance in underlying token units
     */
    function getContractBalance() external view returns (uint256) {
        return _underlying.balanceOf(address(this));
    }

    /**
     * @notice Check if an address is authorized to operate on behalf of an owner
     * @param owner The token owner
     * @param operator The potential operator
     * @return Whether the operator is authorized
     */
    function isAuthorizedFor(address owner, address operator) external view returns (bool) {
        return allowances[owner][operator] || operator == owner;
    }

    /**
     * @dev Get ERC20 decimals from the underlying token with fallback.
     * @param asset The ERC20 token to query
     * @return The number of decimals (defaults to 18 if call fails)
     */
    function _tryGetAssetDecimals(IERC20 asset) internal view returns (uint8) {
        try IERC20Metadata(address(asset)).decimals() returns (uint8 decimals) {
            return decimals;
        } catch {
            (bool success, bytes memory data) = address(asset).staticcall(
                abi.encodeWithSignature("decimals()")
            );
            if (success && data.length >= 32) {
                return abi.decode(data, (uint8));
            }
            return 18; 
        }
    }
}

interface IERC20Metadata {
    function decimals() external view returns (uint8);
}