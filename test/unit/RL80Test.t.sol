// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {DeployRL80} from "script/DeployRL80.s.sol";
import {RL80} from "src/RL80.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {Test, console} from "lib/forge-std/src/Test.sol";
import {Vm} from "lib/forge-std/src/Vm.sol";
import {VRFCoordinatorV2Mock} from "lib/@chainlink/contracts/src/v0.8/mocks/VRFCoordinatorV2Mock.sol";
import {StdCheats} from "lib/forge-std/src/StdCheats.sol";

contract RL80Test is Test {
    event RL80Deployed(address rL80address);
    event RequestSent(uint256 requestId, uint32 numWords);

    error RL80__NoWinningNumbers();
    error RL80__TradingNotEnabled();
    error RL80__ExceedsMaximumHoldingAmount();
    error RL80__TransferAmountBelowMinimum();
    error RL80__AllowanceExceeded();

    RL80 public rL80;
    HelperConfig public helperConfig;
    DeployRL80 deployer;
    // address public bob = makeAddr("bob");
    // address public alice = makeAddr("alice");
    uint256 public constant STARTING_USER_BALANCE = 10000 * 10 ** 18;
    uint256 public TAX_RATE = 300; // 3% tax rate, represented with 2 extra decimals for precision
    uint256 public constant MIN_TRANSFER_AMOUNT = 100 * 10 ** 18; // 100 tokens with decimals
    address public constant TREASURY =
        address(0x70997970C51812dc3A010C7d01b50e0d17dc79C8);

    uint256 public constant MAX_SUPPLY = 10_000_000_000 * 10 ** 18; // 10 billion tokens
    uint256 public tradingStartTime;

    function setUp() external {
        helperConfig = new HelperConfig();
        deployer = new DeployRL80();
        (rL80, helperConfig) = deployer.run();

        (, , , , , uint256 deployerKey) = helperConfig.activeNetworkConfig();

        rL80.toggleTrading(true);
        tradingStartTime = block.timestamp;

        console.log("The test contact address is :", address(this));
        console.log("Contract balance:", rL80.balanceOf(address(this)));
        //Enable trading
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
        vm.warp(tradingStartTime + 1); // Ensure within tax period

        address bob = address(1);
        address alice = address(2);

        uint256 transferAmount = 1000 * 10 ** 18; // 1000 tokens in smallest unit
        rL80.transfer(bob, STARTING_USER_BALANCE); // Give Bob some tokens to transfer

        // Calculate the expected amount Alice should receive after tax
        uint256 taxAmount = (transferAmount * TAX_RATE) / 10000;
        uint256 expectedTransferAmount = transferAmount - taxAmount;

        // Imitate Bob and transfer tokens to Alice
        vm.prank(bob);
        rL80.transfer(alice, transferAmount);

        // Assert that Alice receives the correct post-tax amount
        assertEq(rL80.balanceOf(alice), expectedTransferAmount);
    }

    // Test: Verify that Treasury's balance increases by the tax amount after transfer.
    function testTreasuryReceivesTax() public {
        vm.warp(tradingStartTime + 1); // Ensure within tax period

        address bob = address(1);
        address treasury = TREASURY;

        uint256 initialTreasuryBalance = rL80.balanceOf(treasury);
        rL80.transfer(bob, STARTING_USER_BALANCE); // Give Bob tokens to transfer

        uint256 taxAmount = (1000 * 10 ** 18 * TAX_RATE) / 10000;

        // Imitate Bob and transfer tokens
        vm.prank(bob);
        rL80.transfer(address(2), 1000 * 10 ** 18); // Address of the recipient doesn't matter here

        // Assert Treasury balance increased by the tax amount
        uint256 finalTreasuryBalance = rL80.balanceOf(treasury);
        assertEq(finalTreasuryBalance, initialTreasuryBalance + taxAmount);
    }

    // Test: Verify that Bob's balance decreases by the transferred amount after sending to Alice.
    function testBobBalanceDecreasesByTransferAmount() public {
        vm.warp(tradingStartTime + 1); // Ensure within tax period

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
        bool isTradingEnabled = rL80.tradingEnabled(); // Assuming there's a public getter for the bool tradingEnabled
        assertTrue(isTradingEnabled);
    }

    function testTaxWindowIsActive() public {
        uint256 currentTime = block.timestamp;
        assertTrue(
            currentTime >= rL80.tradingStartTime() &&
                currentTime <= rL80.tradingStartTime() + rL80.TAX_DURATION()
        );
    }

    function testTaxRateConfiguration() public {
        uint256 taxRate = rL80.TAX_RATE(); // Assuming there's a public getter for TAX_RATE
        assertEq(taxRate, 300); // Update the number accordingly to match the expected tax rate
    }

    function testTreasuryAddress() public {
        address treasuryAddress = rL80.treasury(); // Assuming there's a public getter for the treasury address
        assertEq(treasuryAddress, TREASURY);
    }

    function testTaxDeductionLogic() public {
        uint256 amountToTransfer = 1000 * 10 ** 18; // 1000 tokens in smallest unit
        address bob = address(1);
        address alice = address(2);
        rL80.transfer(bob, STARTING_USER_BALANCE);

        uint256 initialBobBalance = rL80.balanceOf(bob);
        uint256 initialAliceBalance = rL80.balanceOf(alice);
        uint256 initialTreasuryBalance = rL80.balanceOf(TREASURY);

        vm.prank(bob);
        rL80.transfer(alice, amountToTransfer);

        uint256 taxAmount = (amountToTransfer * TAX_RATE) / 10000; // Adjust for TAX_RATE unit
        uint256 finalBobBalance = rL80.balanceOf(bob);
        uint256 finalAliceBalance = rL80.balanceOf(alice);
        uint256 finalTreasuryBalance = rL80.balanceOf(TREASURY);

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
        uint256 taxAmount = (transferAmount * TAX_RATE) / 10000;
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

    function testFailTransferFromBelowMinimum() public {
        address bob = address(1);
        address alice = address(2);
        uint256 transferAmount = MIN_TRANSFER_AMOUNT - 1; // Amount below minimum

        // Transfer tokens to Bob
        rL80.transfer(bob, 2 * MIN_TRANSFER_AMOUNT); // Ensure Bob has enough tokens

        // Bob approves the test contract to spend on his behalf
        vm.prank(bob);
        rL80.approve(address(this), 2 * MIN_TRANSFER_AMOUNT);

        // Attempt to transfer an amount below the minimum from Bob to Alice
        rL80.transferFrom(bob, alice, transferAmount); // Should revert
    }

    function testRequestRandomWords() public {
        // Set up an event listener for the RequestSent event
        vm.expectEmit(true, true, true, true);
        emit RequestSent(0, 0); // The parameters here are placeholders

        // Call requestRandomWords
        uint256 requestId = rL80.requestRandomWords();

        // Check if the RequestSent event was emitted with the correct requestId
        // The specific syntax for checking events depends on your testing framework

        // Check if the lastRequestId was updated correctly
        assertEq(rL80.lastRequestId(), requestId);
    }
}
