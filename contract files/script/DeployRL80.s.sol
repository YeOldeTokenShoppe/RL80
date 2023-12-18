// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import {Script} from "contract files/lib/forge-std/src/Script.sol";
import {RL80} from "../src/RL80.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {CreateSubscription, FundSubscription} from "./Interactions.s.sol";

contract DeployRL80 is Script {
    function run() external returns (RL80, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
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

        vm.startBroadcast();

        RL80 rL80 = new RL80(vrfCoordinatorV2, keyHash, subscriptionId);

        vm.stopBroadcast();

        return (rL80, helperConfig);
    }
}
