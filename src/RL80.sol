// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {VRFConsumerBaseV2} from "@chainlink/contracts/src/v0.8/vrf/VRFConsumerBaseV2.sol";
import {VRFCoordinatorV2Interface} from "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";

contract RL80 is ERC20, ERC20Burnable, VRFConsumerBaseV2, Ownable {
    // STRUCTS

    struct RequestStatus {
        bool fulfilled;
        bool exists;
        uint256[] randomWords;
    }

    // ERRORS

    error RL80__TradingNotEnabled();
    error RL80__ExceedsMaximumHoldingAmount();
    error RL80__AllowanceExceeded();
    error RL80__UpkeepNotNeeded(uint256 minimumTokenBalance);

    // MAPPINGS & EVENTS

    mapping(uint256 => RequestStatus) private requests; // requestId -> RequestStatus
    mapping(uint256 => uint256) public sequenceOfWinningNumbers;

    event TradingEnabled(bool enabled);
    event RequestSent(uint256 requestId, uint32 numWords);
    event RequestFulfilled(uint256 requestId, uint256[] randomWords);
    event TokensBurned(
        address indexed burnerAddress,
        uint256 amount,
        uint256 timestamp
    );

    // IMMUTABLE STORAGE

    uint256 public constant MAX_SUPPLY = 10_000_000_000 * 10 ** 18; // 10 billion tokens
    uint256 public constant MAX_HOLDING = MAX_SUPPLY / 100; // 1% of total supply
    uint256 public constant MAX_TAX_RATE = 500; // Maximum tax rate of 5% for safety
    uint256 public constant TAX_DURATION = 40 days; // Duration of the tax period after trading is enabled

    // MUTABLE STORAGE

    uint256 public s_taxRate = 300;
    uint256 public s_reducedTaxRate = 100;
    address public s_treasury = 0xA8d191d2CE9784CE2bC9804d00195BE2805715C0;
    address public s_initialOwner = msg.sender;
    bool public s_tradingEnabled = false;
    uint256[] public s_requestIds;
    uint256 public s_lastRequestId;
    uint256 public s_drawingWeek = 0;
    uint256[] public s_winningNumbers;
    uint256 public s_tradingStartTime;

    // VRF CONSTANTS & IMMUTABLE

    VRFCoordinatorV2Interface private immutable VRF_COORDINATORV2;
    uint64 private immutable VRF_SUBSCRIPTION_ID = 8097;
    bytes32 private immutable VRF_GAS_LANE;
    uint32 private immutable VRF_GAS_LIMIT = 100000;
    uint16 private constant VRF_REQUEST_CONFIRMATIONS = 3;
    uint32 private constant VRF_NUM_WORDS = 1;

    constructor(
        address _vrfCoordinator,
        bytes32 _keyHash,
        uint64 _subscriptionId
    ) ERC20("OurLady", "RL80") VRFConsumerBaseV2(_vrfCoordinator) {
        VRF_COORDINATORV2 = VRFCoordinatorV2Interface(_vrfCoordinator);
        VRF_SUBSCRIPTION_ID = _subscriptionId;
        VRF_GAS_LANE = _keyHash;
        _mint(msg.sender, MAX_SUPPLY);
    }

    // ACTIONS

    function _transferTokens(
        address sender,
        address recipient,
        uint256 amount
    ) private {
        // Check if the sender or recipient is exempt from restrictions
        bool isExemptFromRestrictions = sender == owner() ||
            sender == s_treasury ||
            recipient == s_treasury ||
            sender == s_initialOwner ||
            recipient == s_initialOwner;

        // Check if trading is enabled or if the sender/recipient is exempt
        if (!s_tradingEnabled && !isExemptFromRestrictions) {
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
            s_tradingEnabled &&
            block.timestamp <= s_tradingStartTime + TAX_DURATION
        ) {
            taxAmount = (amount * s_taxRate) / 10000;
        }
        // Check if the current timestamp is beyond the initial tax duration
        else if (
            !isExemptFromRestrictions &&
            s_tradingEnabled &&
            block.timestamp > s_tradingStartTime + TAX_DURATION
        ) {
            taxAmount = (amount * s_reducedTaxRate) / 10000;
        }

        if (taxAmount > 0) {
            transferAmount -= taxAmount;
            super._transfer(sender, s_treasury, taxAmount);
        }

        super._transfer(sender, recipient, transferAmount);
    }

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

    function burn(uint256 amount) public override {
        super.burn(amount);
        emit TokensBurned(_msgSender(), amount, block.timestamp);
    }

    // KEEPERS

    function checkUpkeep(
        bytes memory /* checkData */
    ) public view returns (bool upkeepNeeded, bytes memory /* performData */) {
        // Calculate the current day of the week (0 = Sunday, 1 = Monday, ..., 6 = Saturday)
        uint256 dayOfWeek = (block.timestamp / 86400 + 4) % 7; // Unix time starts on Thursday in 1970

        // Check if it's Sunday
        bool isSunday = (dayOfWeek == 0);

        // Check if it's close to midnight (00:00), with some buffer (e.g., within 15 minutes after midnight)
        uint256 secondsSinceMidnight = block.timestamp % 86400;
        bool isMidnight = (secondsSinceMidnight < 15 * 60);

        // Other conditions
        uint256 minimumTokenBalance = 1000000 * (10 ** 18);
        bool hasBalance = balanceOf(s_treasury) >= minimumTokenBalance;

        // Upkeep is needed if it's Sunday at midnight, and other conditions are met
        upkeepNeeded = (isSunday && isMidnight && hasBalance);
        return (upkeepNeeded, "0x0");
    }

    function performUpkeep(
        bytes calldata /* performData */
    ) external onlyOwner returns (uint256 requestId) {
        (bool upkeepNeeded, ) = checkUpkeep("");
        if (!upkeepNeeded) {
            revert RL80__UpkeepNotNeeded(balanceOf(s_treasury));
        }
        requestId = VRF_COORDINATORV2.requestRandomWords(
            VRF_GAS_LANE,
            VRF_SUBSCRIPTION_ID,
            VRF_REQUEST_CONFIRMATIONS,
            VRF_GAS_LIMIT,
            VRF_NUM_WORDS
        );

        requests[requestId] = RequestStatus({
            randomWords: new uint256[](0),
            exists: true,
            fulfilled: false
        });
        s_requestIds.push(requestId);
        s_lastRequestId = requestId;
        emit RequestSent(requestId, VRF_NUM_WORDS);
        return requestId;
    }

    // VRF

    function fulfillRandomWords(
        uint256 _requestId,
        uint256[] memory _randomWords
    ) internal override {
        if (requests[_requestId].exists) {
            RequestStatus storage request = requests[_requestId];
            request.fulfilled = true;
            request.randomWords = _randomWords;

            // Store the first random word of this drawing in the sequenceOfWinningNumbers mapping
            sequenceOfWinningNumbers[s_drawingWeek] = _randomWords[0];

            // Increment the drawing week counter for the next drawing
            s_drawingWeek++;

            emit RequestFulfilled(_requestId, _randomWords);
        }
    }

    // SETTERS

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
        s_taxRate = _taxRate;
        s_reducedTaxRate = _reducedTaxRate;
    }

    function toggleTrading(bool _enable) external onlyOwner {
        s_tradingEnabled = _enable;
        s_tradingStartTime = _enable ? block.timestamp : 0; // Record the time when trading was enabled, or reset if disabled
        emit TradingEnabled(_enable);
    }

    function setTreasury(address _treasury) external onlyOwner {
        s_treasury = _treasury;
    }

    // GETTERS

    function getBurnedTokens() public view returns (uint256) {
        return MAX_SUPPLY - totalSupply();
    }

    function getWinningNumberForWeek(
        uint256 weekIndex
    ) public view returns (uint256) {
        require(
            weekIndex < s_drawingWeek,
            "Drawing for this week has not occurred yet."
        );
        return sequenceOfWinningNumbers[weekIndex];
    }

    // Public getter function to access request details
    function getRequestDetails(
        uint256 requestId
    ) public view returns (bool, bool, uint256[] memory) {
        RequestStatus storage request = requests[requestId];
        return (request.fulfilled, request.exists, request.randomWords);
    }
}
