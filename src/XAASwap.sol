// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title XAASwap
 * @dev This contract allows users to deposit the native token (DBC) during a 14-day deposit period.
 * After the distribution period begins, users can claim their proportional XAA rewards based on the amount of DBC they deposited.
 */
/// @custom:oz-upgrades-from OldXAASwap
contract XAASwap is Initializable, UUPSUpgradeable, OwnableUpgradeable {
    // Address of the XAA ERC20 token contract
    IERC20 public xaaToken;

    // Total XAA rewards to be distributed: 20 billion XAA (in wei)
    uint256 public constant TOTAL_XAA_REWARD = 20_000_000_000 * 1e18;

    // Deposit period: 14 days
    uint256 public constant DEPOSIT_PERIOD = 14 days;

    // Start and end timestamps for the deposit period
    uint256 public startTime;
    uint256 public endTime;

    // Total amount of DBC deposited in the contract
    uint256 public totalDepositedDBC;
    bool public isStarted;

    // Mapping to store the amount of DBC deposited by each user
    mapping(address => uint256) public userDeposits;

    // Mapping to track whether a user has claimed their XAA rewards
    mapping(address => bool) public hasClaimed;

    // Events
    event Deposit(address indexed user, uint256 amount);
    event RewardsClaimed(address indexed user, uint256 amount);
    event DBCClaimed(uint256 amount);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        // Disable initializers to prevent unauthorized initialization of the implementation contract
        _disableInitializers();
    }

    /**
     * @dev Initializes the contract with the address of the XAA token.
     * This function can only be called once during the deployment process.
     * @param _xaaToken Address of the XAA ERC20 token contract
     */
    function initialize(address owner, address _xaaToken) public initializer {
        __UUPSUpgradeable_init();
        __Ownable_init(owner);

        xaaToken = IERC20(_xaaToken);
    }

    /**
     * @dev Modifier to ensure the function is only called during the deposit period.
     */
    modifier onlyDuringDepositPeriod() {
        require(isStarted, "Distribution not started");
        require(
            block.timestamp >= startTime && block.timestamp <= endTime,
            "Deposit period over"
        );
        _;
    }

    /**
     * @dev Modifier to ensure the function is only called after the distribution period begins.
     */
    modifier onlyAfterDistribution() {
        require(isStarted, "Distribution not started");
        require(block.timestamp > endTime, "Distribution not end");
        _;
    }

    /**
     * @dev Fallback function to accept DBC deposits.
     * Records the deposit and adds the sender to the total deposited amount.
     * Emits a `Deposit` event.
     */
    receive() external payable onlyDuringDepositPeriod {
        require(msg.value > 0, "Must send DBC");

        // Record deposit
        userDeposits[msg.sender] += msg.value;
        totalDepositedDBC += msg.value;

        emit Deposit(msg.sender, msg.value);
    }

    function start(uint256 totalXAAReward) external onlyOwner {
        require(totalXAAReward == TOTAL_XAA_REWARD, "Invalid XAA reward amount");
        require(isStarted == false, "Distribution already started");
        xaaToken.transferFrom(msg.sender, address(this), totalXAAReward);
        isStarted = true;
        startTime = block.timestamp;
        endTime = block.timestamp + DEPOSIT_PERIOD;
    }

    /**
     * @dev Allows users to claim their XAA rewards after the distribution period begins.
     * The amount of XAA is proportional to the amount of DBC they deposited.
     * Emits a `RewardsClaimed` event.
     */
    function claimRewards() external onlyAfterDistribution {
        require(!hasClaimed[msg.sender], "Rewards already claimed");
        require(userDeposits[msg.sender] > 0, "No deposit found");

        uint256 userReward = (userDeposits[msg.sender] * TOTAL_XAA_REWARD) /
            totalDepositedDBC;

        // Mark rewards as claimed
        hasClaimed[msg.sender] = true;

        // Transfer XAA rewards to the user
        require(
            xaaToken.transfer(msg.sender, userReward),
            "XAA transfer failed"
        );

        emit RewardsClaimed(msg.sender, userReward);
    }

    /**
     * @dev Returns the remaining time in the deposit period.
     * @return Remaining time in seconds, or 0 if the deposit period has ended.
     */
    function getRemainingTime() external view returns (uint256) {
        if (isStarted == false) {
            return 0;
        }
        if (block.timestamp > endTime) {
            return 0;
        }
        return endTime - block.timestamp;
    }

    /**
       * @dev Allows the owner (admin) to claim any remaining DBC from the contract.
     * This function can only be called after the deposit period ends.
     */
    function claimDBC() external onlyAfterDistribution onlyOwner {
        uint256 dbcBalance = address(this).balance;
        require(dbcBalance > 0, "No DBC to claim");

        // Transfer all remaining DBC to the owner
        (bool success, ) = msg.sender.call{value: dbcBalance}("");
        require(success, "DBC transfer failed");
        emit DBCClaimed(dbcBalance);
    }

    /**
     * @dev Ensures that only the contract owner can authorize upgrades to the implementation contract.
     * @param newImplementation Address of the new implementation contract.
     */
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}

    function version() public pure returns (uint8) {
        return 0;
    }
}
