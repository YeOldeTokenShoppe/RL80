// SPDX-License-Identifier: MIT

pragma solidity ^0.8.21;

import {DeployRL80} from "contract files/script/DeployRL80.s.sol";
import {RL80} from "contract files/src/RL80.sol";
import {HelperConfig} from "contract files/script/HelperConfig.s.sol";
import {Test, console} from "contract files/lib/forge-std/src/Test.sol";
import {Vm} from "contract files/lib/forge-std/src/Vm.sol";
import {StdCheats} from "contract files/lib/forge-std/src/StdCheats.sol";
import {VRFCoordinatorV2Mock} from "contract files/lib/@chainlink/contracts/src/v0.8/mocks/VRFCoordinatorV2Mock.sol";

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

    // Additional tests for tax logic, holding limit, burn functionality, etc., can be added here.
}
