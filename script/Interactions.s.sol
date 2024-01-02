// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {Script, console} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {RL80} from "../src/RL80.sol";
import {DevOpsTools} from "foundry-devops/src/DevOpsTools.sol";
import {VRFCoordinatorV2Mock} from "@chainlink/contracts/src/v0.8/mocks/VRFCoordinatorV2Mock.sol";
import {LinkToken} from "../test/mocks/LinkToken.sol";

contract CreateSubscription is Script {
    function createSubscriptionUsingConfig() public returns (uint64) {
        HelperConfig helperConfig = new HelperConfig();
        (
            ,
            ,
            ,
            ,
            address VRF_COORDINATORV2,
            ,
            uint256 deployerKey
        ) = helperConfig.activeNetworkConfig();
        return createSubscription(VRF_COORDINATORV2, deployerKey);
    }

    function createSubscription(
        address VRF_COORDINATORV2,
        uint256 deployerKey
    ) public returns (uint64) {
        console.log("Creating subscription on chainId: ", block.chainid);
        vm.startBroadcast(deployerKey);
        uint64 VRF_SUBSCRIPTION_ID = VRFCoordinatorV2Mock(VRF_COORDINATORV2)
            .createSubscription();
        vm.stopBroadcast();
        console.log("Your subscription Id is: ", VRF_SUBSCRIPTION_ID);
        console.log("Please update the subscriptionId in HelperConfig.s.sol");
        return VRF_SUBSCRIPTION_ID;
    }

    function run() external returns (uint64) {
        return createSubscriptionUsingConfig();
    }
}

contract AddConsumer is Script {
    function addConsumer(
        address contractToAddToVrf,
        address VRF_COORDINATORV2,
        uint64 VRF_SUBSCRIPTION_ID,
        uint256 deployerKey
    ) public {
        console.log("Adding consumer contract: ", contractToAddToVrf);
        console.log("Using vrfCoordinator: ", VRF_COORDINATORV2);
        console.log("On ChainID: ", block.chainid);
        vm.startBroadcast(deployerKey);
        VRFCoordinatorV2Mock(VRF_COORDINATORV2).addConsumer(
            VRF_SUBSCRIPTION_ID,
            contractToAddToVrf
        );
        vm.stopBroadcast();
    }

    function addConsumerUsingConfig(address mostRecentlyDeployed) public {
        HelperConfig helperConfig = new HelperConfig();
        (
            uint64 VRF_SUBSCRIPTION_ID,
            ,
            ,
            ,
            address VRF_COORDINATORV2,
            ,
            uint256 deployerKey
        ) = helperConfig.activeNetworkConfig();
        addConsumer(
            mostRecentlyDeployed,
            VRF_COORDINATORV2,
            VRF_SUBSCRIPTION_ID,
            deployerKey
        );
    }

    function run() external {
        address mostRecentlyDeployed = DevOpsTools.get_most_recent_deployment(
            "RL80",
            block.chainid
        );
        addConsumerUsingConfig(mostRecentlyDeployed);
    }
}

contract FundSubscription is Script {
    uint96 public constant FUND_AMOUNT = 3 ether;

    function fundSubscriptionUsingConfig() public {
        HelperConfig helperConfig = new HelperConfig();
        (
            uint64 VRF_SUBSCRIPTION_ID,
            ,
            ,
            ,
            address VRF_COORDINATORV2,
            address link,
            uint256 deployerKey
        ) = helperConfig.activeNetworkConfig();
        fundSubscription(
            VRF_COORDINATORV2,
            VRF_SUBSCRIPTION_ID,
            link,
            deployerKey
        );
    }

    function fundSubscription(
        address VRF_COORDINATORV2,
        uint64 VRF_SUBSCRIPTION_ID,
        address link,
        uint256 deployerKey
    ) public {
        console.log("Funding subscription: ", VRF_SUBSCRIPTION_ID);
        console.log("Using vrfCoordinator: ", VRF_COORDINATORV2);
        console.log("On ChainID: ", block.chainid);
        if (block.chainid == 31337) {
            vm.startBroadcast(deployerKey);
            VRFCoordinatorV2Mock(VRF_COORDINATORV2).fundSubscription(
                VRF_SUBSCRIPTION_ID,
                FUND_AMOUNT
            );
            vm.stopBroadcast();
        } else {
            console.log(LinkToken(link).balanceOf(msg.sender));
            console.log(msg.sender);
            console.log(LinkToken(link).balanceOf(address(this)));
            console.log(address(this));
            vm.startBroadcast(deployerKey);
            LinkToken(link).transferAndCall(
                VRF_COORDINATORV2,
                FUND_AMOUNT,
                abi.encode(VRF_SUBSCRIPTION_ID)
            );
            vm.stopBroadcast();
        }
    }

    function run() external {
        fundSubscriptionUsingConfig();
    }
}
