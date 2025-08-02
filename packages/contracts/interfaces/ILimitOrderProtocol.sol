// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

interface ILimitOrderProtocol {
    struct Order {
        uint256 salt;
        address makerAsset;
        address takerAsset;
        address maker;
        address receiver;
        address allowedSender;
        uint256 makingAmount;
        uint256 takingAmount;
        uint256 offsets;
        bytes interactions;
    }
    
    function fillOrder(
        Order memory order,
        bytes calldata signature,
        bytes calldata interaction,
        uint256 makingAmount,
        uint256 takingAmount,
        uint256 thresholdAmount
    ) external payable returns (uint256 actualMakingAmount, uint256 actualTakingAmount);
    
    function cancelOrder(Order memory order) external;
    
    function hashOrder(Order memory order) external view returns (bytes32);
}