// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {FHE, externalEuint64, euint64, ebool} from "@fhevm/solidity/lib/FHE.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {ConfidentialFungibleTokenERC20Wrapper} from "@openzeppelin/confidential-contracts/token/ConfidentialFungibleTokenERC20Wrapper.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title AscendaConfidentialCollateral
 * @dev Confidential wrapper for USDC/USDT collateral used in Ascenda derivatives
 * Users can deposit regular USDC and get confidential cUSDC tokens for private trading
 */
contract AscendaConfidentialCollateral is ConfidentialFungibleTokenERC20Wrapper, Ownable {
    mapping(address => bool) public authorizedContracts;
    
    event ContractAuthorized(address indexed contractAddress, bool authorized);
    event ConfidentialDeposit(address indexed user, euint64 amount);
    event ConfidentialWithdrawal(address indexed user, euint64 amount);
    
    modifier onlyAuthorized() {
        require(authorizedContracts[msg.sender] || msg.sender == owner(), "Not authorized");
        _;
    }
    
    constructor(
        IERC20 underlying_,
        string memory name_,
        string memory symbol_,
        string memory tokenURI_
    ) 
        ConfidentialFungibleTokenERC20Wrapper(underlying_) 
        ConfidentialFungibleToken(name_, symbol_, tokenURI_)
    {}
    
    /**
     * @dev Authorize contracts to interact with confidential balances
     */
    function setContractAuthorization(address contractAddress, bool authorized) external onlyOwner {
        authorizedContracts[contractAddress] = authorized;
        emit ContractAuthorized(contractAddress, authorized);
    }
    
    /**
     * @dev Enhanced wrap function with confidential deposit event
     */
    function confidentialDeposit(address to, uint256 amount) external {
        wrap(to, amount);
        euint64 confidentialAmount = FHE.asEuint64(amount / rate());
        emit ConfidentialDeposit(to, confidentialAmount);
    }
    
    /**
     * @dev Enhanced unwrap for authorized contracts
     */
    function confidentialWithdrawFrom(
        address from,
        address to,
        euint64 amount
    ) external onlyAuthorized {
        require(
            FHE.isAllowed(amount, address(this)),
            "Contract not authorized for amount"
        );
        _unwrap(from, to, amount);
        emit ConfidentialWithdrawal(from, amount);
    }
    
    /**
     * @dev Transfer confidential collateral between authorized contracts
     */
    function authorizedTransfer(
        address from,
        address to,
        euint64 amount
    ) external onlyAuthorized returns (euint64) {
        require(
            FHE.isAllowed(amount, address(this)),
            "Contract not authorized for amount"
        );
        return _transfer(from, to, amount);
    }
    
    /**
     * @dev Batch operations for gas efficiency
     */
    function batchWrap(
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external {
        require(recipients.length == amounts.length, "Array length mismatch");
        
        uint256 totalAmount = 0;
        for (uint256 i = 0; i < amounts.length; i++) {
            totalAmount += amounts[i] - (amounts[i] % rate());
        }
        
        IERC20(underlying()).transferFrom(msg.sender, address(this), totalAmount);
        
        for (uint256 i = 0; i < recipients.length; i++) {
            euint64 confidentialAmount = FHE.asEuint64(amounts[i] / rate());
            _mint(recipients[i], confidentialAmount);
            emit ConfidentialDeposit(recipients[i], confidentialAmount);
        }
    }
}
