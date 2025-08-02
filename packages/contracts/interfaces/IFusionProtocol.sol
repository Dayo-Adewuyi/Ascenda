// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IFusionProtocol {
    struct FusionOrder {
        uint256 salt;
        address makerAsset;
        address takerAsset;
        bytes makerAssetData;
        bytes takerAssetData;
        bytes getMakerAmount;
        bytes getTakerAmount;
        bytes predicate;
        bytes permit;
        bytes interactions;
    }
    
    function fillOrder(
        FusionOrder memory order,
        bytes calldata signature,
        uint256 makingAmount,
        uint256 takingAmount
    ) external payable returns (uint256, uint256);
}