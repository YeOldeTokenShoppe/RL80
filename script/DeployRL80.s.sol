// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import {Script} from "lib/forge-std/src/Script.sol";
import {RL80} from "../src/RL80.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {AddConsumer, CreateSubscription, FundSubscription} from "./Interactions.s.sol";
import {Test, console} from "lib/forge-std/src/Test.sol";

contract DeployRL80 is Script {
    RL80 public rL80;

    constructor() {
        // Log the deployer's address for debugging
        console.log("DeployRL80 contract deployed by:", msg.sender);
    }

    function run() external returns (RL80, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        AddConsumer addConsumer = new AddConsumer();
        uint privateKey = vm.envUint("PRIVATE_KEY");
        address account = vm.addr(privateKey);

        console.log("Account: ", account);

        (
            uint64 subscriptionId,
            bytes32 keyHash,
            ,
            address vrfCoordinatorV2,
            address link,
            uint256 deployerKey
        ) = helperConfig.activeNetworkConfig();

        if (subscriptionId == 0) {
            CreateSubscription createSubscription = new CreateSubscription();
            subscriptionId = createSubscription.createSubscription(
                vrfCoordinatorV2,
                deployerKey
            );

            FundSubscription fundSubscription = new FundSubscription();
            fundSubscription.fundSubscription(
                vrfCoordinatorV2,
                subscriptionId,
                link,
                deployerKey
            );
        }

        vm.startBroadcast(deployerKey);

        rL80 = new RL80(vrfCoordinatorV2, keyHash, subscriptionId);
        //Transfer minted supply to the Test Contract
        rL80.transfer(
            address(0x34A1D3fff3958843C43aD80F30b94c510645C316), // Transfer tokens to the Test Contract
            10_000_000_000 * 1e18
        );
        console.log(
            "Owner of RL80 contract immediately after deployment:",
            rL80.owner()
        );
        rL80.transferOwnership(
            address(0x34A1D3fff3958843C43aD80F30b94c510645C316)
        );

        // Transfer the tokens
        // rL80.transfer(
        //     address(0xb4c79daB8f259C7Aee6E5b2Aa729821864227e84), // Transfer tokens to the Test Contract
        //     10_000_000_000 * 1e18
        // );

        // Add the contract to the exempt list

        vm.stopBroadcast();

        addConsumer.addConsumer(
            address(rL80),
            vrfCoordinatorV2,
            subscriptionId,
            deployerKey
        );
        console.log("Owner of RL80 contract:", rL80.owner());
        return (rL80, helperConfig);
    }

    function transferRL80Ownership(address newOwner) external {
        rL80.transferOwnership(newOwner);
    }
}
