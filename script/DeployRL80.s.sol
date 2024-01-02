// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import {Script} from "forge-std/Script.sol";
import {RL80} from "../src/RL80.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {AddConsumer, CreateSubscription, FundSubscription} from "./Interactions.s.sol";

contract DeployRL80 is Script {
    RL80 public rL80;

    function run() external returns (RL80, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        AddConsumer addConsumer = new AddConsumer();
        // uint privateKey = vm.envUint("PRIVATE_KEY");
        // address account = vm.addr(privateKey);

        // console.log("Account: ", account);

        (
            uint64 VRF_SUBSCRIPTION_ID,
            bytes32 VRF_GAS_LANE,
            uint256 automationUpdateInterval,
            ,
            address VRF_COORDINATORV2,
            address link,
            uint256 deployerKey
        ) = helperConfig.activeNetworkConfig();

        if (VRF_SUBSCRIPTION_ID == 0) {
            CreateSubscription createSubscription = new CreateSubscription();
            VRF_SUBSCRIPTION_ID = createSubscription.createSubscription(
                VRF_COORDINATORV2,
                deployerKey
            );

            FundSubscription fundSubscription = new FundSubscription();
            fundSubscription.fundSubscription(
                VRF_COORDINATORV2,
                VRF_SUBSCRIPTION_ID,
                link,
                deployerKey
            );
        }

        vm.startBroadcast(deployerKey);

        rL80 = new RL80(
            VRF_COORDINATORV2,
            VRF_GAS_LANE,
            automationUpdateInterval
        );
        // Transfer minted supply to the Test Contract or the deployer
        rL80.transfer(
            address(0x5Ad34D42bAF12ABBFA65B7649C58235C0Db75D6C),
            10_000_000_000 * 1e18
        );

        rL80.transferOwnership(
            address(0x5Ad34D42bAF12ABBFA65B7649C58235C0Db75D6C)
        );

        vm.stopBroadcast();

        addConsumer.addConsumer(
            address(rL80),
            VRF_COORDINATORV2,
            VRF_SUBSCRIPTION_ID,
            deployerKey
        );

        return (rL80, helperConfig);
    }

    function transferRL80Ownership(address newOwner) external {
        rL80.transferOwnership(newOwner);
    }
}
