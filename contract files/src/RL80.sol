// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {ERC20} from "contract files/lib/@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "contract files/lib/@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "contract files/lib/@openzeppelin/contracts/access/Ownable.sol";
import {VRFConsumerBaseV2} from "contract files/lib/@chainlink/contracts/src/v0.8/vrf/VRFConsumerBaseV2.sol";
import {VRFCoordinatorV2Interface} from "contract files/lib/@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";

contract RL80 is ERC20, ERC20Burnable, VRFConsumerBaseV2, Ownable {
    error RL80__NoWinningNumbers();
    error RL80__TradingNotEnabled();
    error RL80__ExceedsMaximumHoldingAmount();

    uint256 public constant MAX_SUPPLY = 10_000_000_000 * 10 ** 18; // 10 billion tokens
    uint256 public constant MAX_HOLDING = MAX_SUPPLY / 100; // 1% of total supply
    uint256 public constant TAX_RATE = 300; // 3% tax rate, represented with 2 extra decimals for precision
    uint256 public constant TAX_DURATION = 40 days; // Duration of the tax period after trading is enabled

    address public treasury = 0x412B323356fcbF559D624376CF99Ba471A1C57B3;
    address public initialOwner = msg.sender;
    bool public tradingEnabled = false;
    uint256 public tradingStartTime;

    // Chainlink Variables
    VRFCoordinatorV2Interface private coordinator;
    uint64 private s_subscriptionId;
    bytes32 private keyHash;
    uint32 private callbackGasLimit = 100000;
    uint16 private requestConfirmations = 3;
    uint32 private numWords = 1;
    uint256[] public requestIds;
    uint256 public lastRequestId;

    mapping(uint256 => RequestStatus) private requests; // requestId -> RequestStatus
    struct RequestStatus {
        bool fulfilled;
        bool exists;
        uint256[] randomWords;
    }
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
        _mint(msg.sender, MAX_SUPPLY); // Mint the total supply to the deployer, who is the owner by default
    }

    // Custom transfer function to apply token tax and holding limit
    function _transferTokens(
        address sender,
        address recipient,
        uint256 amount
    ) private {
        if (!(tradingEnabled || sender == owner() || sender == treasury)) {
            revert RL80__TradingNotEnabled();
        }

        if (
            !(balanceOf(recipient) + amount <= MAX_HOLDING ||
                recipient == owner() ||
                recipient == treasury)
        ) {
            revert RL80__ExceedsMaximumHoldingAmount();
        }

        uint256 transferAmount = amount;
        if (
            sender != owner() &&
            sender != treasury &&
            tradingEnabled &&
            block.timestamp <= tradingStartTime + TAX_DURATION
        ) {
            uint256 taxAmount = (amount * TAX_RATE) / 10000;
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

    // New transferFrom function
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public override returns (bool) {
        uint256 currentAllowance = allowance(sender, _msgSender());
        require(
            currentAllowance >= amount,
            "RL80: transfer amount exceeds allowance"
        );
        _approve(sender, _msgSender(), currentAllowance - amount);
        _transferTokens(sender, recipient, amount);
        return true;
    }

    // Allow trading to be enabled by the contract owner
    function toggleTrading(bool _enable) public onlyOwner {
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
    function requestRandomWords() external returns (uint256 requestId) {
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

    receive() external payable {}
}
