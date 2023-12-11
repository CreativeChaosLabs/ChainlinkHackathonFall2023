// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract BBCoinFlip is ReentrancyGuard, Ownable, VRFConsumerBaseV2 {
    VRFCoordinatorV2Interface COORDINATOR;
    uint64 private SUBSCRIPTION_ID;
    bytes32 private KEY_HASH;

    uint32 private constant CALLBACK_GAS_LIMIT = 100000;
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1;

    struct BBCoinFlipGame {
        uint256 amount;
        bool choice; // true for heads
    }

    mapping(uint256 => address) private requestIdToSender;
    mapping(address => BBCoinFlipGame) private playerBets;

    event BetPlaced(address indexed player, uint256 amount, bool choice);
    event BetResolved(address indexed player, uint256 amountWon, bool win);
    event FundsDeposited(address sender, uint256 amount);

    error WagerAboveLimit(uint256 wager, uint256 maxWager);

    constructor(
        address vrfCoordinator, 
        bytes32 keyHash,
        address initialOwner, 
        uint64 subscriptionId 
    ) Ownable(initialOwner) VRFConsumerBaseV2(vrfCoordinator) {
        COORDINATOR = VRFCoordinatorV2Interface(vrfCoordinator);
        SUBSCRIPTION_ID = subscriptionId;
        KEY_HASH = keyHash;
    }

    // Public view function to calculate and return the max wager using kelly fraction
    function get_max_wager() public view returns (uint256) {
        uint256 balance = address(this).balance;
        return (balance * 1122448) / 100000000;
    }

    function place_bet(bool choice) external payable nonReentrant {
        require(msg.value > 0, "Bet amount must be greater than 0");
        uint256 maxWager = get_max_wager();
        require(msg.value <= maxWager, "Bet exceeds maximum wager limit");

        playerBets[msg.sender] = BBCoinFlipGame(msg.value, choice);
        uint256 requestId = requestRandomWords();
        requestIdToSender[requestId] = msg.sender;
        emit BetPlaced(msg.sender, msg.value, choice);
    }

    function requestRandomWords() public returns (uint256) {
        return COORDINATOR.requestRandomWords(KEY_HASH, SUBSCRIPTION_ID, REQUEST_CONFIRMATIONS, CALLBACK_GAS_LIMIT, NUM_WORDS);
    }

    function fulfillRandomWords(uint256 requestId, uint256[] memory randomWords) internal override {
        address player = requestIdToSender[requestId];
        BBCoinFlipGame memory bet = playerBets[player];
        bool winningChoice = (randomWords[0] % 2 == 0);

        if (winningChoice == bet.choice) {
            payable(player).transfer(bet.amount * 2);
            emit BetResolved(player, bet.amount * 2, true);
        } else {
            emit BetResolved(player, 0, false);
        }

        delete requestIdToSender[requestId];
        delete playerBets[player];
    }

    function deposit_funds() external payable onlyOwner {
        emit FundsDeposited(msg.sender, msg.value);
    }

    function withdraw_funds(uint256 amount) external onlyOwner {
        require(amount <= address(this).balance, "Insufficient funds to withdraw");
        payable(msg.sender).transfer(amount);
    }

    receive() external payable {
        emit FundsDeposited(msg.sender, msg.value);
    }
    
}