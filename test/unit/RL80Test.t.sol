// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {DeployRL80} from "script/DeployRL80.s.sol";
import {RL80} from "src/RL80.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {Test, console} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {VRFCoordinatorV2Mock} from "@chainlink/contracts/src/v0.8/mocks/VRFCoordinatorV2Mock.sol";
import {StdCheats} from "forge-std/StdCheats.sol";

contract RL80Test is Test {
    event RL80Deployed(address rL80address);
    event TradingEnabled(bool enabled);
    event RequestSent(uint256 requestId, uint32 numWords);
    event RequestFulfilled(uint256 requestId, uint256[] randomWords);
    event TokensBurned(
        address indexed burner,
        uint256 amount,
        uint256 timestamp
    );

    error RL80__TradingNotEnabled();
    error RL80__ExceedsMaximumHoldingAmount();
    error RL80__AllowanceExceeded();

    RL80 public rL80;
    HelperConfig public helperConfig;
    DeployRL80 deployer;

    uint64 VRF_SUBSCRIPTION_ID;
    bytes32 VRF_GAS_LANE;
    uint32 VRF_GAS_LIMIT;
    address VRF_COORDINATORV2;
    uint256 automationUpdateInterval;
    address link;
    uint256 deployerKey;

    uint256 public constant STARTING_USER_BALANCE = 10000 * 10 ** 18;
    uint256 public constant MAX_TAX_RATE = 500; // Maximum tax rate of 5% for safety

    uint256 public s_taxRate = 300; // 3% initial tax rate
    uint256 public s_reducedTaxRate = 100; // 1% reduced tax
    uint256 public constant TAX_DURATION = 40 days; // Duration of the tax period after trading is enabled
    uint256 public constant MAX_HOLDING = MAX_SUPPLY / 100; // 1% of total supply

    address public constant s_treasury =
        address(0xA8d191d2CE9784CE2bC9804d00195BE2805715C0);

    uint256 public constant MAX_SUPPLY = 10_000_000_000 * 10 ** 18; // 10 billion tokens
    uint256 public s_tradingStartTime;

    modifier skipFork() {
        if (block.chainid != 31337) {
            return;
        }
        _;
    }

    function setUp() external {
        helperConfig = new HelperConfig();
        deployer = new DeployRL80();
        (rL80, helperConfig) = deployer.run();

        (
            VRF_SUBSCRIPTION_ID,
            VRF_GAS_LANE,
            automationUpdateInterval,
            VRF_GAS_LIMIT,
            VRF_COORDINATORV2, //link
            //deployerKey
            ,

        ) = helperConfig.activeNetworkConfig();

        // rL80.toggleTrading(true);
        s_tradingStartTime = block.timestamp;
    }

    function testOwnershipTransfer() public {
        rL80.renounceOwnership();
        assertEq(rL80.owner(), address(0)); // Owner should be 0x0
    }

    function testInitialBalanceToBob() public {
        address bob = address(1);
        rL80.transfer(bob, STARTING_USER_BALANCE);
        assertEq(rL80.balanceOf(bob), STARTING_USER_BALANCE);
    }

    function testBobTransfersToAlice() public {
        address bob = address(1);
        address alice = address(2);
        rL80.transfer(bob, STARTING_USER_BALANCE);
        rL80.transfer(alice, 1000 * 10 ** 18);
        assertEq(rL80.balanceOf(alice), 1000 * 10 ** 18);
    }

    // Test: Verify that Bob has the expected starting balance.
    function testBobStartingBalance() public {
        address bob = address(1);

        rL80.transfer(bob, STARTING_USER_BALANCE);

        assertEq(rL80.balanceOf(bob), STARTING_USER_BALANCE);
    }

    // Test: Verify that Alice's balance increases by the expected amount after Bob's transfer.
    function testAliceReceivesCorrectAmountPostTax() public {
        vm.warp(s_tradingStartTime + 1); // Ensure within tax period

        address bob = address(1);
        address alice = address(2);

        uint256 transferAmount = 1000 * 10 ** 18; // 1000 tokens in smallest unit
        rL80.transfer(bob, STARTING_USER_BALANCE); // Give Bob some tokens to transfer

        // Calculate the expected amount Alice should receive after tax
        uint256 taxAmount = (transferAmount * s_taxRate) / 10000;
        uint256 expectedTransferAmount = transferAmount - taxAmount;

        // Imitate Bob and transfer tokens to Alice
        vm.prank(bob);
        rL80.transfer(alice, transferAmount);

        // Assert that Alice receives the correct post-tax amount
        assertEq(rL80.balanceOf(alice), expectedTransferAmount);
    }

    // Test: Verify that Treasury's balance increases by the tax amount after transfer.
    function testTreasuryReceivesTax() public {
        vm.warp(s_tradingStartTime + 1); // Ensure within tax period

        address bob = address(1);
        address treasury = s_treasury;

        uint256 initialTreasuryBalance = rL80.balanceOf(treasury);
        rL80.transfer(bob, STARTING_USER_BALANCE); // Give Bob tokens to transfer

        uint256 taxAmount = (1000 * 10 ** 18 * s_taxRate) / 10000;

        // Imitate Bob and transfer tokens
        vm.prank(bob);
        rL80.transfer(address(2), 1000 * 10 ** 18); // Address of the recipient doesn't matter here

        // Assert Treasury balance increased by the tax amount
        uint256 finalTreasuryBalance = rL80.balanceOf(treasury);
        assertEq(finalTreasuryBalance, initialTreasuryBalance + taxAmount);
    }

    // Test: Verify that Bob's balance decreases by the transferred amount after sending to Alice.
    function testBobBalanceDecreasesByTransferAmount() public {
        vm.warp(s_tradingStartTime + 1); // Ensure within tax period

        address bob = address(1);
        address alice = address(2);

        // Set up Bob's starting balance
        rL80.transfer(bob, STARTING_USER_BALANCE);

        // Calculate Bob's expected balance after transfer
        uint256 expectedBobBalance = STARTING_USER_BALANCE - 1000 * 10 ** 18; // Not accounting for tax, since Bob pays it

        // Imitate Bob and transfer tokens to Alice
        vm.prank(bob);
        rL80.transfer(alice, 1000 * 10 ** 18);

        // Assert that Bob's balance is correct after the transfer
        assertEq(rL80.balanceOf(bob), expectedBobBalance);
    }

    function testTradingIsEnabled() public {
        bool isTradingEnabled = rL80.s_tradingEnabled(); // Assuming there's a public getter for the bool tradingEnabled
        assertTrue(isTradingEnabled);
    }

    function testTaxWindowIsActive() public {
        uint256 currentTime = block.timestamp;
        assertTrue(
            currentTime >= rL80.s_tradingStartTime() &&
                currentTime <= rL80.s_tradingStartTime() + rL80.TAX_DURATION()
        );
    }

    function testTreasuryAddress() public {
        address treasuryAddress = rL80.s_treasury(); // Assuming there's a public getter for the treasury address
        assertEq(treasuryAddress, s_treasury);
    }

    function testTaxDeductionLogic() public {
        uint256 amountToTransfer = 1000 * 10 ** 18; // 1000 tokens in smallest unit
        address bob = address(1);
        address alice = address(2);
        rL80.transfer(bob, STARTING_USER_BALANCE);

        uint256 initialBobBalance = rL80.balanceOf(bob);
        uint256 initialAliceBalance = rL80.balanceOf(alice);
        uint256 initialTreasuryBalance = rL80.balanceOf(s_treasury);

        vm.prank(bob);
        rL80.transfer(alice, amountToTransfer);

        uint256 taxAmount = (amountToTransfer * s_taxRate) / 10000; // Adjust for TAX_RATE unit
        uint256 finalBobBalance = rL80.balanceOf(bob);
        uint256 finalAliceBalance = rL80.balanceOf(alice);
        uint256 finalTreasuryBalance = rL80.balanceOf(s_treasury);

        // Check that Bob's balance is reduced by the full amount, including tax
        assertEq(finalBobBalance, initialBobBalance - amountToTransfer);

        // Check that Alice's balance is increased only by the net amount (after tax)
        assertEq(
            finalAliceBalance,
            initialAliceBalance + (amountToTransfer - taxAmount)
        );

        // Optionally, check the Treasury's balance increase by the tax amount
        assertEq(finalTreasuryBalance, initialTreasuryBalance + taxAmount);
    }

    function testTradingNotEnabled() public {
        address bob = address(1); // Define Bob's address
        uint256 transferAmount = 1000 * 10 ** 18; // Set the transfer amount, including decimals

        rL80.transfer(bob, transferAmount); // First, transfer tokens to Bob to set up his balance
        rL80.toggleTrading(false); // Disable trading

        vm.prank(bob); // Impersonate Bob for the next transaction
        vm.expectRevert(RL80__TradingNotEnabled.selector); // Expect the transaction to revert due to trading being disabled

        rL80.transfer(address(2), transferAmount); // Bob attempts to transfer tokens to another address
    }

    function testBurn() public {
        address bob = address(1);
        uint256 transferAmount = 1000 * 10 ** 18;

        // Transfer tokens to Bob
        rL80.transfer(bob, transferAmount);

        // Record the total supply before burning
        uint256 initialTotalSupply = rL80.totalSupply();

        // Impersonate Bob and burn his tokens
        vm.prank(bob);
        rL80.burn(transferAmount);

        // Assert that Bob's balance is now 0
        assertEq(rL80.balanceOf(bob), 0);

        // Assert that the total supply has decreased by the burned amount
        assertEq(rL80.totalSupply(), initialTotalSupply - transferAmount);
    }

    function testFailBurnMoreThanBalance() public {
        address bob = address(1);
        uint256 transferAmount = 1000 * 10 ** 18;
        uint256 burnAmount = transferAmount + 1 * 10 ** 18; // Set burn amount greater than balance

        // Transfer tokens to Bob
        rL80.transfer(bob, transferAmount);

        // Impersonate Bob and attempt to burn more tokens than his balance
        vm.prank(bob);
        rL80.burn(burnAmount); // This should revert
    }

    function testGetBurnedTokens() public {
        address bob = address(1);
        uint256 initialBurnedTokens = rL80.getBurnedTokens();
        uint256 amountToBurn = 500 * 10 ** 18; // Amount of tokens to burn

        // Transfer tokens to Bob
        rL80.transfer(bob, amountToBurn);

        // Impersonate Bob and burn some of his tokens
        vm.prank(bob);
        rL80.burn(amountToBurn);

        // Calculate the expected burned tokens
        uint256 expectedBurnedTokens = initialBurnedTokens + amountToBurn;

        // Assert that getBurnedTokens returns the correct amount
        assertEq(rL80.getBurnedTokens(), expectedBurnedTokens);
    }

    function testTransferFrom() public {
        address bob = address(1);
        address alice = address(2);
        uint256 transferAmount = 1000 * 10 ** 18; // Adjust as per your token's decimals
        uint256 taxAmount = (transferAmount * s_taxRate) / 10000;
        // Transfer tokens to Bob
        rL80.transfer(bob, transferAmount);

        // Bob approves the test contract to spend on his behalf
        vm.prank(bob);
        rL80.approve(address(this), transferAmount);

        // Test contract transfers from Bob to Alice
        rL80.transferFrom(bob, alice, transferAmount);

        // Check Alice's balance
        assertEq(rL80.balanceOf(alice), transferAmount - taxAmount);
    }

    function testFailTransferFromInsufficientAllowance() public {
        address bob = address(1);
        address alice = address(2);
        uint256 transferAmount = 1000 * 10 ** 18;

        // Transfer tokens to Bob
        rL80.transfer(bob, transferAmount);

        // Bob approves the test contract to spend less than transferAmount
        vm.prank(bob);
        rL80.approve(address(this), transferAmount / 2);

        // Attempt to transfer more than the approved amount from Bob to Alice
        rL80.transferFrom(bob, alice, transferAmount); // Should revert
    }

    function testFulfillRandomWordsGetsRequestId(
        uint256 randomRequestId
    ) public skipFork {
        // address vrfCoordinatorV2 = 0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0;
        vm.expectRevert("nonexistent request");
        VRFCoordinatorV2Mock(VRF_COORDINATORV2).fulfillRandomWords(
            randomRequestId,
            address(rL80)
        );
    }

    // function testWinningNumberRecordedCorrectly() public skipFork {
    //     // Set up conditions for checkUpkeep to return true
    //     // Arrange: Set the time to Sunday at midnight
    //     address treasury = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
    //     rL80.transfer(treasury, 1000000 * 10 ** 18);
    //     uint256 currentDay = (block.timestamp / 86400 + 4) % 7;
    //     uint256 daysToNextSunday = (7 - currentDay) % 7;
    //     if (daysToNextSunday == 0) {
    //         daysToNextSunday = 7; // If today is Sunday, warp to next Sunday
    //     }
    //     uint256 nextSundayMidnight = block.timestamp + daysToNextSunday * 86400;
    //     vm.warp(nextSundayMidnight);

    //     // Call requestRandomWords and get the request ID
    //     rL80.requestRandomWords();
    //     uint256 requestId;
    //     assertTrue(requestId > 0, "Request ID should be greater than zero");

    //     // Simulate the VRF Coordinator fulfilling the request
    //     VRFCoordinatorV2Mock(VRF_COORDINATORV2).fulfillRandomWords(
    //         requestId,
    //         address(rL80)
    //     );

    //     // Retrieve the details of the request
    //     (bool fulfilled, bool exists, uint256[] memory randomWords) = rL80
    //         .getRequestDetails(requestId);

    //     // Assert that the request was fulfilled and exists
    //     assertTrue(fulfilled, "Request was not fulfilled");
    //     assertTrue(exists, "Request does not exist");

    //     // Assert that a random word was recorded
    //     assertTrue(randomWords.length > 0, "No random word recorded");
    // }

    function testTaxIsReducedAfterTaxDuration() public {
        vm.warp(s_tradingStartTime + rL80.TAX_DURATION() + 1); // Warp to after tax duration

        address bob = address(1);
        address alice = address(2);

        uint256 transferAmount = 1000 * 10 ** 18; // 1000 tokens in smallest unit
        rL80.transfer(bob, STARTING_USER_BALANCE); // Give Bob some tokens to transfer

        // Calculate the expected amount Alice should receive after tax
        uint256 taxAmount = (transferAmount * s_reducedTaxRate) / 10000;
        uint256 expectedTransferAmount = transferAmount - taxAmount;

        // Imitate Bob and transfer tokens to Alice
        vm.prank(bob);
        rL80.transfer(alice, transferAmount);

        // Assert that Alice receives the correct post-tax amount
        assertEq(rL80.balanceOf(alice), expectedTransferAmount);

        // Assert that the tax rate is reduced
        assertEq(rL80.s_reducedTaxRate(), 100); // Assuming the reduced tax rate is 1%
    }

    function testFailTransferExceedsMaximumHoldingAmount() public {
        address bob = address(1);
        address alice = address(2);

        // Transfer tokens to Bob
        rL80.transfer(bob, MAX_HOLDING);

        // Attempt to transfer tokens from Bob to Alice
        vm.prank(bob);
        rL80.transfer(alice, MAX_HOLDING);

        // Attempt second transfer from Bob to Alice
        vm.prank(bob);
        rL80.transfer(alice, MAX_HOLDING);
    }

    function testSetTaxRates() public {
        uint256 newTaxRate = 200; // 2% tax rate
        uint256 newReducedTaxRate = 150; // 1% reduced tax rate

        rL80.setTaxRates(newTaxRate, newReducedTaxRate);

        assertEq(rL80.s_taxRate(), newTaxRate);
        assertEq(rL80.s_reducedTaxRate(), newReducedTaxRate);
    }

    function testFailSetTaxRatesAbove500() public {
        uint256 newTaxRate = 600; // 100.01% tax rate
        uint256 newReducedTaxRate = 150; // 1% reduced tax rate

        vm.expectRevert("tax rate above 500");
        rL80.setTaxRates(newTaxRate, newReducedTaxRate);
    }

    function testOwnerCanTransferTokensWhenTradingNotEnabled() public {
        rL80.toggleTrading(false);
        rL80.transfer(address(2), 1000 * 10 ** 18);
        //address(2) should have 1000 tokens
        assertEq(rL80.balanceOf(address(2)), 1000 * 10 ** 18);
    }

    // function testRequestRandomWordsReturnsRequestId() public {
    //     uint256 requestId = rL80.requestRandomWords();
    //     assertEq(rL80.lastRequestId(), requestId);
    // }

    function testTransferOverTransferMinimum() public {
        address bob = address(1);
        address alice = address(2);
        uint256 transferAmount = 1000 * 10 ** 18; // Adjust as per your token's decimals
        uint256 taxAmount = (transferAmount * s_taxRate) / 10000;
        // Transfer tokens to Bob
        rL80.transfer(bob, transferAmount);

        // Bob approves the test contract to spend on his behalf
        vm.prank(bob);
        rL80.approve(address(this), transferAmount);

        // Test contract transfers from Bob to Alice
        rL80.transferFrom(bob, alice, transferAmount);

        // Check Alice's balance
        assertEq(rL80.balanceOf(alice), transferAmount - taxAmount);
    }

    function testFailTransferFromAllowanceExceeded() public {
        address owner = address(1);
        address spender = address(2);
        address recipient = address(3);
        uint256 allowanceAmount = 1000 * 10 ** 18; // Owner allows spender to spend 1000 tokens
        uint256 transferAmount = allowanceAmount + 1 * 10 ** 18; // Spender tries to transfer 1001 tokens

        // Transfer tokens to the owner
        rL80.transfer(owner, transferAmount);

        // Owner approves the spender to spend a specific amount
        vm.prank(owner);
        rL80.approve(spender, allowanceAmount);

        // Spender attempts to transfer more than the allowance from the owner's account
        vm.prank(spender);
        rL80.transferFrom(owner, recipient, transferAmount); // Should revert with RL80__AllowanceExceeded
    }

    // function testRequestRandomWordsCannotBeCalledbyNonOwner() public {
    //     address nonOwner = address(2);
    //     vm.prank(nonOwner);
    //     vm.expectRevert("Ownable: caller is not the owner");
    //     rL80.requestRandomWords();
    // }

    function testTransferIfAllowanceNotExceeded() public {
        address owner = address(1);
        address spender = address(2);
        address recipient = address(3);
        uint256 allowanceAmount = 1000 * 10 ** 18; // Owner allows spender to spend 1000 tokens
        uint256 transferAmount = allowanceAmount; // Spender tries to transfer 1000 tokens

        // Transfer tokens to the owner
        rL80.transfer(owner, transferAmount);

        // Owner approves the spender to spend a specific amount
        vm.prank(owner);
        rL80.approve(spender, allowanceAmount);

        // Spender attempts to transfer the allowance amount from the owner's account
        vm.prank(spender);
        rL80.transferFrom(owner, recipient, transferAmount); // Should succeed
    }

    function testTokensBurnedEvent() public {
        address burner = address(1);
        uint256 burnAmount = 100 * 10 ** 18; // Adjust as per your token's decimals

        // Transfer tokens to the burner for the burn operation
        rL80.transfer(burner, burnAmount);

        // Simulate the burner burning some tokens
        vm.recordLogs();
        vm.prank(burner);
        rL80.burn(burnAmount); // Replace with your contract's burn function call

        // Retrieve and check the logs
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 2, "Incorrect number of logs emitted");

        // Check the TokensBurned event
        bytes32 expectedEventSignature = keccak256(
            "TokensBurned(address,uint256,uint256)"
        );
        assertEq(
            logs[1].topics[0],
            expectedEventSignature,
            "Incorrect event signature"
        );

        // Correctly extract and compare the burner address from the log
        address loggedBurnerAddress = address(
            uint160(uint256(logs[1].topics[1]))
        );
        assertEq(loggedBurnerAddress, burner, "Incorrect burner address");

        // Decode the data field for amount and timestamp
        (uint256 loggedAmount /*uint256 loggedTimestamp*/, ) = abi.decode(
            logs[1].data,
            (uint256, uint256)
        );
        assertEq(loggedAmount, burnAmount, "Incorrect burn amount");
        // Timestamp check might need adjustment based on how your contract emits the event
    }

    // function testCheckUpkeepReturnsFalseIfItHasNoBalance() public {
    //     // Arrange: Set the time to Sunday at midnight
    //     uint256 currentDay = (block.timestamp / 86400 + 4) % 7;
    //     uint256 daysToNextSunday = (7 - currentDay) % 7;
    //     if (daysToNextSunday == 0) {
    //         daysToNextSunday = 7; // If today is Sunday, warp to next Sunday
    //     }
    //     uint256 nextSundayMidnight = block.timestamp + daysToNextSunday * 86400;
    //     vm.warp(nextSundayMidnight);

    //     // Ensure the treasury has no balance
    //     // Note: This depends on how your contract handles token balances.
    //     // You might need to transfer tokens out of the treasury or set it up accordingly.

    //     // Act: Call checkUpkeep
    //     (bool upkeepNeeded, ) = rL80.checkUpkeep("");

    //     // Assert: checkUpkeep should return false
    //     assert(!upkeepNeeded);
    // }

    // function testCheckUpkeepReturnsFalseIfLotteryIsntOpen() public {
    //     // Arrange: Set the time to Sunday at midnight
    //     uint256 currentDay = (block.timestamp / 86400 + 4) % 7;
    //     uint256 daysToNextSunday = (7 - currentDay) % 7;
    //     if (daysToNextSunday == 0) {
    //         daysToNextSunday = 7; // If today is Sunday, warp to next Sunday
    //     }
    //     uint256 nextSundayMidnight = block.timestamp + daysToNextSunday * 86400;
    //     vm.warp(nextSundayMidnight);

    //     // Ensure the treasury has a balance
    //     // Note: This depends on how your contract handles token balances.
    //     // You might need to transfer tokens out of the treasury or set it up accordingly.

    //     // Act: Call checkUpkeep
    //     (bool upkeepNeeded, ) = rL80.checkUpkeep("");

    //     // Assert: checkUpkeep should return false
    //     assert(!upkeepNeeded);
    // }

    // function testCheckUpkeepReturnsTrueWhenParametersGood() public skipFork {
    //     // Transfer tokens to the treasury
    //     address treasury = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
    //     rL80.transfer(treasury, 1000000 * 10 ** 18);

    //     // Set the time to the next Sunday at midnight
    //     uint256 currentDay = (block.timestamp / 86400 + 4) % 7;
    //     uint256 daysToNextSunday = (7 - currentDay) % 7;
    //     uint256 nextSundayMidnight = block.timestamp + daysToNextSunday * 86400;
    //     if (daysToNextSunday == 0) {
    //         nextSundayMidnight += 7 * 86400; // If today is Sunday, warp to next Sunday
    //     }
    //     vm.warp(nextSundayMidnight);

    //     // Call checkUpkeep
    //     (bool upkeepNeeded, ) = rL80.checkUpkeep("");

    //     // Assert: checkUpkeep should return true
    //     assert(upkeepNeeded);
    // }

    // function testPerformUpkeepRevertsIfCheckUpkeepIsFalse() public skipFork {
    //     // Arrange: Set the time to a day other than Sunday
    //     uint256 currentDay = (block.timestamp / 86400 + 4) % 7;
    //     uint256 daysToNextNonSunday = (currentDay == 0) ? 1 : 0; // If today is Sunday, warp to Monday
    //     uint256 nextNonSundayMidnight = block.timestamp +
    //         daysToNextNonSunday *
    //         86400;
    //     vm.warp(nextNonSundayMidnight);

    //     // Act & Assert: Call performUpkeep and expect it to revert with the specific error
    //     // Assuming the error RL80__UpkeepNotNeeded takes a single uint256 parameter which is 0
    //     bytes memory expectedRevertData = abi.encodeWithSignature(
    //         "RL80__UpkeepNotNeeded(uint256)",
    //         0
    //     );

    //     vm.expectRevert(expectedRevertData);
    //     rL80.performUpkeep("");
    // }

    // function testPerformUpkeepDoesNotRevertIfCheckUpkeepIsTrue()
    //     public
    //     skipFork
    // {
    //     address treasury = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
    //     rL80.transfer(treasury, 1000000 * 10 ** 18);
    //     // Arrange: Set the time to Sunday at midnight
    //     uint256 currentDay = (block.timestamp / 86400 + 4) % 7;
    //     uint256 daysToNextSunday = (7 - currentDay) % 7;
    //     if (daysToNextSunday == 0) {
    //         daysToNextSunday = 7; // If today is Sunday, warp to next Sunday
    //     }
    //     uint256 nextSundayMidnight = block.timestamp + daysToNextSunday * 86400;
    //     vm.warp(nextSundayMidnight);

    //     // Act & Assert: Call performUpkeep and expect it not to revert
    //     rL80.performUpkeep("");
    // }

    // function testPerformUpkeepEmitsRequestId() public skipFork {
    //     address treasury = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
    //     rL80.transfer(treasury, 1000000 * 10 ** 18);
    //     // Arrange: Set the time to Sunday at midnight
    //     uint256 currentDay = (block.timestamp / 86400 + 4) % 7;
    //     uint256 daysToNextSunday = (7 - currentDay) % 7;
    //     if (daysToNextSunday == 0) {
    //         daysToNextSunday = 7; // If today is Sunday, warp to next Sunday
    //     }
    //     uint256 nextSundayMidnight = block.timestamp + daysToNextSunday * 86400;
    //     vm.warp(nextSundayMidnight);

    //     // Act: Call performUpkeep and record logs
    //     vm.recordLogs();
    //     rL80.performUpkeep("");

    //     // Assert: RequestId event is emitted
    //     Vm.Log[] memory logs = vm.getRecordedLogs();
    //     bool foundRequestIdEvent = false;
    //     for (uint i = 0; i < logs.length; i++) {
    //         if (logs[i].topics[0] == keccak256("RequestSent(uint256,uint32)")) {
    //             foundRequestIdEvent = true;
    //             break;
    //         }
    //     }
    //     if (!foundRequestIdEvent) {
    //         revert("RequestSent event not emitted");
    //     }
    // }

    // function testFulfillRandomWordsCanOnlyBeCalledAfterPerformUpkeep()
    //     public
    //     skipFork
    // {
    //     // Arrange
    //     // Act / Assert
    //     vm.expectRevert("nonexistent request");
    //     // vm.mockCall could be used here...
    //     VRFCoordinatorV2Mock(VRF_COORDINATORV2).fulfillRandomWords(
    //         0,
    //         address(rL80)
    //     );

    //     vm.expectRevert("nonexistent request");

    //     VRFCoordinatorV2Mock(VRF_COORDINATORV2).fulfillRandomWords(
    //         1,
    //         address(rL80)
    //     );
    // }

    function testExemptFromMaxHolding() public {
        address treasury = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
        // Arrange: Calculate an amount greater than 1% of MAX_SUPPLY
        uint256 excessAmount = rL80.MAX_SUPPLY() / 100 + 1; // 1% of MAX_SUPPLY plus 1

        // Act: Transfer excess amount to exempt addresses
        rL80.transfer(treasury, excessAmount);
        rL80.transfer(address(rL80), excessAmount); // If the contract itself is exempt

        // Assert: Check if the balances of these addresses exceed the max holding
        assert(rL80.balanceOf(treasury) > rL80.MAX_HOLDING());
        assert(rL80.balanceOf(address(rL80)) > rL80.MAX_HOLDING());
    }

    function testFailIfNotExemptFromMaxHolding() public {
        // Arrange: Calculate an amount close to but not exceeding 1% of MAX_SUPPLY
        uint256 maxHolding = rL80.MAX_SUPPLY() / 100; // 1% of MAX_SUPPLY

        // Calculate the gross amount to transfer to result in maxHolding after tax
        uint256 initialAmount = (maxHolding * 10000) / (10000 - s_taxRate);
        uint256 additionalAmount = 1; // Small amount to exceed the limit after tax

        address nonExemptAddress = address(1);
        address sender1 = address(2); // Or another address with sufficient tokens
        address sender2 = address(3); // Or another address with sufficient tokens

        // Ensure sender1 and sender2 have enough tokens
        // Assuming setup steps to allocate tokens to sender1 and sender2

        // Act: Transfer initial amount to non-exempt address
        vm.prank(sender1);
        rL80.transfer(nonExemptAddress, initialAmount);

        // Assert: Attempt to transfer additional amount and expect it to revert
        vm.expectRevert("RL80__ExceedsMaximumHoldingAmount");
        vm.prank(sender2);
        rL80.transfer(nonExemptAddress, additionalAmount);
    }
}
