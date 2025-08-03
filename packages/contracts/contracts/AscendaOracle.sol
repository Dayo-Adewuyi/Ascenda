// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../interfaces/IAscendaOracle.sol";

contract AscendaOracle is  Ownable, ReentrancyGuard, IAscendaOracle {
    mapping(string => address) public symbolToOracle;
    mapping(string => PriceData) public priceData;
    mapping(address => bool) public authorized;
    
    uint256 public constant PRICE_STALENESS_THRESHOLD = 3600; 
    
    event PriceUpdated(string indexed symbol, uint256 price, uint256 timestamp);
    event OracleSet(string indexed symbol, address oracle);
    event AuthorizedUpdated(address indexed account, bool authorized);
    
    modifier onlyAuthorized() {
        require(authorized[msg.sender] || msg.sender == owner(), "Not authorized");
        _;
    }
    
    constructor() Ownable(msg.sender) {
        authorized[msg.sender] = true;
    }
    
    function setAuthorized(address account, bool _authorized) external onlyOwner {
        authorized[account] = _authorized;
        emit AuthorizedUpdated(account, _authorized);
    }
    
    function setSymbolOracle(string memory symbol, address oracle) external onlyOwner {
        symbolToOracle[symbol] = oracle;
        emit OracleSet(symbol, oracle);
    }
    
    function getPrice(string memory symbol) external view returns (PriceData memory) {
        address oracleAddress = symbolToOracle[symbol];
        
        if (oracleAddress != address(0)) {
            AggregatorV3Interface priceFeed = AggregatorV3Interface(oracleAddress);
            
            try priceFeed.latestRoundData() returns (
                uint80,
                int256 price,
                uint256,
                uint256 updatedAt,
                uint80
            ) {
                require(price > 0, "Invalid price");
                require(block.timestamp - updatedAt <= PRICE_STALENESS_THRESHOLD, "Stale price");
                
                return PriceData({
                    price: uint256(price),
                    timestamp: updatedAt,
                    decimals: priceFeed.decimals(),
                    isValid: true
                });
            } catch {
                PriceData memory fallbackData = priceData[symbol];
                require(fallbackData.isValid, "No valid price data");
                require(block.timestamp - fallbackData.timestamp <= PRICE_STALENESS_THRESHOLD, "Stale fallback price");
                return fallbackData;
            }
        } else {
            PriceData memory storedData = priceData[symbol];
            require(storedData.isValid, "No valid price data");
            require(block.timestamp - storedData.timestamp <= PRICE_STALENESS_THRESHOLD, "Stale stored price");
            return storedData;
        }
    }
    
    function updatePrice(string memory symbol, uint256 price) external onlyAuthorized nonReentrant {
        require(price > 0, "Invalid price");
        
        priceData[symbol] = PriceData({
            price: price,
            timestamp: block.timestamp,
            decimals: 8,
            isValid: true
        });
        
        emit PriceUpdated(symbol, price, block.timestamp);
    }
    
    function isSymbolSupported(string memory symbol) external view returns (bool) {
        return symbolToOracle[symbol] != address(0) || priceData[symbol].isValid;
    }
    
    function batchUpdatePrices(
        string[] memory symbols,
        uint256[] memory prices
    ) external onlyAuthorized nonReentrant {
        require(symbols.length == prices.length, "Array length mismatch");
        
        for (uint256 i = 0; i < symbols.length; i++) {
            require(prices[i] > 0, "Invalid price");
            
            priceData[symbols[i]] = PriceData({
                price: prices[i],
                timestamp: block.timestamp,
                decimals: 8,
                isValid: true
            });
            
            emit PriceUpdated(symbols[i], prices[i], block.timestamp);
        }
    }
}