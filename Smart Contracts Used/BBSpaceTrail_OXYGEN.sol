// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract SpaceTrail is ReentrancyGuard, Ownable, VRFConsumerBaseV2 {
    VRFCoordinatorV2Interface COORDINATOR;
    uint64 private SUBSCRIPTION_ID;
    bytes32 private KEY_HASH;

    uint32 private constant CALLBACK_GAS_LIMIT = 100000;
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1;

    enum TrailChoice { WorkWithOthers, FixItYourself, Ignore, BePanic}

    struct SpaceTrailGame {
        uint256 amount;
        TrailChoice choice;
    }

    mapping(uint256 => address) private requestIdToSender;
    mapping(address => SpaceTrailGame) private playerBets;

    event BetPlaced(address indexed player, uint256 amount, TrailChoice choice);
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

    // Function to calculate the maximum wager based on choice
    function getMaxWager() public view returns (uint256) {
        uint256 balance = address(this).balance;
        return balance * 500000 / 100000000; // Using the provided Kelly fraction
    }

    // Helper function to get the Kelly fraction based on the choice
    function getKellyFraction(TrailChoice choice) public pure returns (uint256) {
        if (choice == TrailChoice.WorkWithOthers) return 40499999; // 0.40499999
        if (choice == TrailChoice.FixItYourself) return 24499999; // 0.24499999
        if (choice == TrailChoice.Ignore) return 4499989; // 0.04499989
        if (choice == TrailChoice.BePanic) return 500000; // 0.005
        return 0; // Default
    }

    function placeBet(TrailChoice choice) external payable nonReentrant {
        require(msg.value > 0, "Bet amount must be greater than 0");
        
        // Passing 'choice' as an argument to getMaxWager
        uint256 maxWager = getMaxWager();
        require(msg.value <= maxWager, "Bet exceeds maximum wager limit");

        playerBets[msg.sender] = SpaceTrailGame(msg.value, choice);
        uint256 requestId = requestRandomWords();
        requestIdToSender[requestId] = msg.sender;
        emit BetPlaced(msg.sender, msg.value, choice);
    }

    function requestRandomWords() private returns (uint256 requestId) {
        // Requesting randomness
        requestId = COORDINATOR.requestRandomWords(
            KEY_HASH,
            SUBSCRIPTION_ID,
            REQUEST_CONFIRMATIONS,
            CALLBACK_GAS_LIMIT,
            NUM_WORDS
        );

        return requestId;
    }

    function fulfillRandomWords(uint256 requestId, uint256[] memory randomWords) internal override {
        address player = requestIdToSender[requestId];
        SpaceTrailGame memory game = playerBets[player];

        uint256 randomNumber = randomWords[0] % 100;
        uint256 payoutMultiplier = getPayoutMultiplier(game.choice);
        uint256 successChance = getSuccessChance(game.choice);

        if (randomNumber < successChance) {
            uint256 payout = game.amount * payoutMultiplier / 100; // Correct scaling
            payable(player).transfer(payout);
            emit BetResolved(player, payout, true);
        } else {
            emit BetResolved(player, 0, false);
        }

        delete requestIdToSender[requestId];
        delete playerBets[player];
    }

    function getPayoutMultiplier(TrailChoice choice) public pure returns (uint256) {
        if (choice == TrailChoice.WorkWithOthers) return 111; // Scaled up version of 1.11
        if (choice == TrailChoice.FixItYourself) return 142; // Scaled up version of 1.42
        if (choice == TrailChoice.Ignore) return 333; // Scaled up version of 3.33
        if (choice == TrailChoice.BePanic) return 1000; // Scaled up version of 10.00
        return 100; // Scaled up version of 1.00
    }

    function getSuccessChance(TrailChoice choice) public pure returns (uint256) {
        if (choice == TrailChoice.WorkWithOthers) return 90;
        if (choice == TrailChoice.FixItYourself) return 70;
        if (choice == TrailChoice.Ignore) return 30;
        if (choice == TrailChoice.BePanic) return 10;
        return 100; // Default 
    }

    function depositFunds() external payable onlyOwner {
        emit FundsDeposited(msg.sender, msg.value);
    }

    function withdrawFunds(uint256 amount) external onlyOwner {
        require(amount <= address(this).balance, "Insufficient funds to withdraw");
        payable(msg.sender).transfer(amount);
    }

    receive() external payable {
        emit FundsDeposited(msg.sender, msg.value);
    }
}