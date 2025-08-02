// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IAscendaOracle {
    struct PriceData {
        uint256 price;
        uint256 timestamp;
        uint256 decimals;
        bool isValid;
    }
    
    function getPrice(string memory symbol) external view returns (PriceData memory);
    function updatePrice(string memory symbol, uint256 price) external;
    function setSymbolOracle(string memory symbol, address oracle) external;
    function isSymbolSupported(string memory symbol) external view returns (bool);
}
