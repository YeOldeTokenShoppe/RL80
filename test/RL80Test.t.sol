// SPDX-License-Identifier: MIT

pragma solidity ^0.8.21;

import {DeployRL80} from "../../script/DeployRL80.s.sol";
import {RL80} from "../../src/RL80.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {Test, console} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {VRFCoordinatorV2Mock} from "lib/@chainlink/contracts/src/v0.8/mocks/VRFCoordinatorV2Mock.sol";

contract RL80Test is StdCheats, Test {
    RL80 public rL80;
    HelperConfig public helperConfig;

    event TradingEnabled(bool enabled);
    event RandomnessRequested(uint256 requestId);
    event WinningNumber(uint256 requestId, uint256[] randomWords);

    function setUp() external {
        DeployRL80 deployer = new DeployRL80();
        (rL80, helperConfig) = deployer.run();
    }

    function testInitialSupply() public {
        assertEq(rL80.totalSupply(), 10_000_000_000 * 10 ** 18);
    }

    function testInitialBalance() public {
        assertEq(rL80.balanceOf(address(this)), 10_000_000_000 * 10 ** 18);
    }

    function testTransferWithTradingDisabled() public {
        // Assuming trading is disabled initially
        vm.expectRevert("RL80__TradingNotEnabled");
        rL80.transfer(address(0x1), 1 ether);
    }

    function testEnableTradingAndTransfer() public {
        rL80.enableTrading();
        assertTrue(rL80.tradingEnabled());

        uint256 transferAmount = 1 ether;
        rL82Token.transfer(address(0x1), transferAmount);
        assertEq(rL80.balanceOf(address(0x1)), transferAmount);
    }

    // Additional tests for tax logic, holding limit, burn functionality, etc., can be added here.
}
