// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {VRFConsumerBaseV2} from "@chainlink/contracts/src/v0.8/vrf/VRFConsumerBaseV2.sol";
import {VRFCoordinatorV2Interface} from "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";

contract RL80 is ERC20, ERC20Burnable, VRFConsumerBaseV2, Ownable {
    error RL80__NoWinningNumbers();
    error RL80__TradingNotEnabled();
    error RL80__ExceedsMaximumHoldingAmount();
    error RL80__AllowanceExceeded();

    uint256 public constant MAX_SUPPLY = 10_000_000_000 * 10 ** 18; // 10 billion tokens
    uint256 public constant MAX_HOLDING = MAX_SUPPLY / 100; // 1% of total supply
    uint256 public constant MAX_TAX_RATE = 500; // Maximum tax rate of 5% for safety
    uint256 public constant TAX_DURATION = 40 days; // Duration of the tax period after trading is enabled
    // uint256 public constant MIN_TRANSFER_AMOUNT = 100 * 10 ** 18; // 100 tokens with decimals

    uint256 public taxRate = 300; // 3% initial tax rate
    uint256 public reducedTaxRate = 100; // 1% reduced tax rate

    address public treasury = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8; //this is anvil address number 2
    address public initialOwner = msg.sender;
    bool public tradingEnabled = false;
    uint256 public tradingStartTime;
    address private DefaultTestContract =
        0xb4c79daB8f259C7Aee6E5b2Aa729821864227e84;
    address private TestContract = 0x34A1D3fff3958843C43aD80F30b94c510645C316;

    // Chainlink Variables
    VRFCoordinatorV2Interface private coordinator;
    uint64 private s_subscriptionId = 8097;
    bytes32 private keyHash;
    uint32 private callbackGasLimit = 100000;
    uint16 private requestConfirmations = 3;
    uint32 private numWords = 1;
    uint256[] public requestIds;
    uint256 public lastRequestId;

    struct RequestStatus {
        bool fulfilled;
        bool exists;
        uint256[] randomWords;
    }

    mapping(uint256 => RequestStatus) private requests; // requestId -> RequestStatus

    uint256[] public winningNumbers;

    event TradingEnabled(bool enabled);
    event RequestSent(uint256 requestId, uint32 numWords);
    event RequestFulfilled(uint256 requestId, uint256[] randomWords);
    event TokensBurned(
        address indexed burner,
        uint256 amount,
        uint256 timestamp
    );

    constructor(
        address _vrfCoordinator,
        bytes32 _keyHash,
        uint64 _subscriptionId
    ) ERC20("OurLady", "RL80") VRFConsumerBaseV2(_vrfCoordinator) {
        coordinator = VRFCoordinatorV2Interface(_vrfCoordinator);
        s_subscriptionId = _subscriptionId;
        keyHash = _keyHash;
        _mint(msg.sender, MAX_SUPPLY);
    }

    function _transferTokens(
        address sender,
        address recipient,
        uint256 amount
    ) private {
        // Check if the sender or recipient is exempt from restrictions
        bool isExemptFromRestrictions = sender == owner() ||
            sender == treasury ||
            sender == DefaultTestContract ||
            recipient == DefaultTestContract ||
            recipient == TestContract ||
            sender == TestContract;

        // Check if trading is enabled or if the sender/recipient is exempt
        if (!tradingEnabled && !isExemptFromRestrictions) {
            revert RL80__TradingNotEnabled();
        }

        // Check for maximum holding amount unless the recipient is exempt
        if (
            balanceOf(recipient) + amount > MAX_HOLDING &&
            !isExemptFromRestrictions
        ) {
            revert RL80__ExceedsMaximumHoldingAmount();
        }

        uint256 transferAmount = amount;
        uint256 taxAmount = 0;

        // Apply tax if not exempt and within tax duration
        if (
            !isExemptFromRestrictions &&
            tradingEnabled &&
            block.timestamp <= tradingStartTime + TAX_DURATION
        ) {
            taxAmount = (amount * taxRate) / 10000;
        }
        // Check if the current timestamp is beyond the initial tax duration
        else if (
            !isExemptFromRestrictions &&
            tradingEnabled &&
            block.timestamp > tradingStartTime + TAX_DURATION
        ) {
            taxAmount = (amount * reducedTaxRate) / 10000;
        }

        if (taxAmount > 0) {
            transferAmount -= taxAmount;
            super._transfer(sender, treasury, taxAmount);
        }

        super._transfer(sender, recipient, transferAmount);
    }

    // Overridden transfer function
    function transfer(
        address recipient,
        uint256 amount
    ) public override returns (bool) {
        _transferTokens(_msgSender(), recipient, amount);
        return true;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public override returns (bool) {
        uint256 currentAllowance = allowance(sender, _msgSender());
        if (currentAllowance < amount) revert RL80__AllowanceExceeded();
        _approve(sender, _msgSender(), currentAllowance - amount);
        _transferTokens(sender, recipient, amount);
        return true;
    }

    // Allow trading to be enabled by the contract owner
    function toggleTrading(bool _enable) external onlyOwner {
        tradingEnabled = _enable;
        tradingStartTime = _enable ? block.timestamp : 0; // Record the time when trading was enabled, or reset if disabled
        emit TradingEnabled(_enable);
    }

    // Token burn function for lotteries and contests
    function burn(uint256 amount) public override {
        super.burn(amount);
        emit TokensBurned(_msgSender(), amount, block.timestamp);
    }

    // Request randomness for the lottery using Chainlink VRF -  WILL NEED TO CHANGE THIS _ REMOVE onlyOWner and make private
    function requestRandomWords()
        external
        onlyOwner
        returns (uint256 requestId)
    {
        requestId = coordinator.requestRandomWords(
            keyHash,
            s_subscriptionId,
            requestConfirmations,
            callbackGasLimit,
            numWords
        );

        requests[requestId] = RequestStatus({
            randomWords: new uint256[](0),
            exists: true,
            fulfilled: false
        });
        requestIds.push(requestId);
        lastRequestId = requestId;
        emit RequestSent(requestId, numWords);
        return requestId;
    }

    // Fulfill randomness using Chainlink VRF
    function fulfillRandomWords(
        uint256 _requestId,
        uint256[] memory _randomWords
    ) internal override {
        if (requests[_requestId].exists) {
            RequestStatus storage request = requests[_requestId];
            request.fulfilled = true;
            request.randomWords = _randomWords;
            winningNumbers.push(_randomWords[0]); // Assuming the first random word is used for the lottery

            emit RequestFulfilled(_requestId, _randomWords);
        }
    }

    function getBurnedTokens() public view returns (uint256) {
        return MAX_SUPPLY - totalSupply();
    }

    // Public getter function to access request details
    function getRequestDetails(
        uint256 requestId
    ) public view returns (bool, bool, uint256[] memory) {
        RequestStatus storage request = requests[requestId];
        return (request.fulfilled, request.exists, request.randomWords);
    }

    function setTaxRates(
        uint256 _taxRate,
        uint256 _reducedTaxRate
    ) external onlyOwner {
        require(
            _taxRate <= MAX_TAX_RATE,
            "RL80: Tax rate exceeds maximum limit"
        );
        require(
            _reducedTaxRate <= MAX_TAX_RATE,
            "RL80: Reduced tax rate exceeds maximum limit"
        );
        taxRate = _taxRate;
        reducedTaxRate = _reducedTaxRate;
    }

    receive() external payable {}
}
