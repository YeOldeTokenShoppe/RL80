// 1. Deploy mocks when we are on a local anvil chain
// 2. Deploy the real contracts when we are on a testnet or mainnet
//3. Keep track of the deployed addresses so we can use them in our tests

//If we are on a local anvil, we deploy  mocks
//Otherwise, grab the existing address from the live networks

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {VRFCoordinatorV2Mock} from "lib/@chainlink/contracts/src/v0.8/mocks/VRFCoordinatorV2Mock.sol";
import {LinkToken} from "../test/mocks/LinkToken.sol";
import {Script} from "lib/forge-std/Script.sol";

contract HelperConfig is Script {
    struct NetworkConfig {
        uint64 VRF_SUBSCRIPTION_ID;
        bytes32 VRF_GAS_LANE;
        uint256 automationUpdateInterval;
        uint32 VRF_GAS_LIMIT;
        address VRF_COORDINATORV2;
        address link;
        uint256 deployerKey;
    }

    uint256 public DEFAULT_ANVIL_PRIVATE_KEY =
        0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    NetworkConfig public activeNetworkConfig;

    event HelperConfig__CreatedMockVRFCoordinator(address vrfCoordinator);

    constructor() {
        if (block.chainid == 11155111) {
            activeNetworkConfig = getSepoliaEthConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilEthConfig();
        }
    }

    function getMainnetEthConfig()
        public
        view
        returns (NetworkConfig memory mainnetNetworkConfig)
    {
        mainnetNetworkConfig = NetworkConfig({
            VRF_SUBSCRIPTION_ID: 899, // If left as 0, our scripts will create one!
            VRF_GAS_LANE: 0xff8dedfbfa60af186cf3c830acbc32c05aae823045ae5ea7da1e45fbfaba4f92,
            automationUpdateInterval: 1 weeks, // 1 week
            VRF_GAS_LIMIT: 500000, // 500,000 gas
            VRF_COORDINATORV2: 0x271682DEB8C4E0901D1a1550aD2e64D568E69909,
            link: 0x514910771AF9Ca656af840dff83E8264EcF986CA,
            deployerKey: vm.envUint("PRIVATE_KEY")
        });
    }

    function getSepoliaEthConfig()
        public
        view
        returns (NetworkConfig memory sepoliaNetworkConfig)
    {
        sepoliaNetworkConfig = NetworkConfig({
            VRF_SUBSCRIPTION_ID: 8097, // If left as 0, our scripts will create one!
            VRF_GAS_LANE: 0x474e34a077df58807dbe9c96d3c009b23b3c6d0cce433e59bbf5b34f823bc56c,
            automationUpdateInterval: 600, // seconds
            VRF_GAS_LIMIT: 500000, // 500,000 gas
            VRF_COORDINATORV2: 0x8103B0A8A00be2DDC778e6e7eaa21791Cd364625,
            link: 0x779877A7B0D9E8603169DdbD7836e478b4624789,
            deployerKey: vm.envUint("PRIVATE_KEY")
        });
    }

    function getOrCreateAnvilEthConfig()
        public
        returns (NetworkConfig memory anvilNetworkConfig)
    {
        // Check to see if we set an active network config
        if (activeNetworkConfig.VRF_COORDINATORV2 != address(0)) {
            return activeNetworkConfig;
        }

        uint96 baseFee = 0.25 ether; // 0.25 LINK
        uint96 gasPriceLink = 1e9; // 1 gwei LINK

        vm.startBroadcast(DEFAULT_ANVIL_PRIVATE_KEY);
        VRFCoordinatorV2Mock vrfCoordinatorV2Mock = new VRFCoordinatorV2Mock(
            baseFee,
            gasPriceLink
        );

        LinkToken link = new LinkToken();
        vm.stopBroadcast();

        emit HelperConfig__CreatedMockVRFCoordinator(
            address(vrfCoordinatorV2Mock)
        );

        anvilNetworkConfig = NetworkConfig({
            VRF_SUBSCRIPTION_ID: 0, // If left as 0, our scripts will create one!
            VRF_GAS_LANE: 0x474e34a077df58807dbe9c96d3c009b23b3c6d0cce433e59bbf5b34f823bc56c, // doesn't really matter
            automationUpdateInterval: 300, // 30 seconds
            VRF_GAS_LIMIT: 500000, // 500,000 gas
            VRF_COORDINATORV2: address(vrfCoordinatorV2Mock),
            link: address(link),
            deployerKey: DEFAULT_ANVIL_PRIVATE_KEY
        });
    }
}
