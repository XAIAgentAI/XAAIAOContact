// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/IAO.sol";
import {MockERC20} from "forge-std/mocks/MockERC20.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract XAASwapTest is Test {
    IAO public xaaSwap;
    MockERC20 public xaaToken;

    address public owner = address(0x1);
    address public user1 = address(0x2);
    address public user2 = address(0x3);

    uint256 public constant TOTAL_XAA_REWARD = 20_000_000_000 * 1e18;
    uint256 public constant DEPOSIT_PERIOD = 14 days;
    uint256 public constant DISTRIBUTION_START_DELAY = 144 hours;

    function setUp() public {
        // Deploy mock XAA token and XAASwap contract
        xaaToken = new MockERC20();
        vm.startPrank(owner);

        ERC1967Proxy proxy = new ERC1967Proxy(
            address(new IAO()),
            abi.encodeWithSelector(
                IAO.initialize.selector,
                owner,
                address(xaaToken)
            )
        );
        xaaSwap = IAO(payable(address(proxy)));
        // Transfer total XAA rewards to the contract
        deal(address(xaaToken), address(xaaSwap), TOTAL_XAA_REWARD);
        vm.stopPrank();
    }

    function testInitialize() public view {
        assertEq(address(xaaSwap.rewardToken()), address(xaaToken));
        assertEq(xaaSwap.startTime(), block.timestamp);
        assertEq(xaaSwap.endTime(), block.timestamp + DEPOSIT_PERIOD);
    }

    function testDepositDBC() public {
        vm.deal(user1, 10 ether);

        vm.startPrank(user1);
        (bool success, ) = address(xaaSwap).call{value: 5 ether}("");
        require(success, "Deposit failed");
        vm.stopPrank();

        assertEq(xaaSwap.userDeposits(user1), 5 ether);
        assertEq(xaaSwap.totalDepositedDBC(), 5 ether);
    }
    function testMultipleDeposits() public {
        vm.deal(user1, 10 ether);
        vm.deal(user2, 20 ether);

        vm.startPrank(user1);
        (bool success1, ) = address(xaaSwap).call{value: 5 ether}("");
        require(success1, "User1 deposit failed");
        vm.stopPrank();

        vm.startPrank(user2);
        (bool success2, ) = address(xaaSwap).call{value: 10 ether}("");
        require(success2, "User2 deposit failed");
        vm.stopPrank();

        assertEq(xaaSwap.userDeposits(user1), 5 ether);
        assertEq(xaaSwap.userDeposits(user2), 10 ether);
        assertEq(xaaSwap.totalDepositedDBC(), 15 ether);
    }
    function testClaimRewards() public {
        // Simulate deposits
        vm.deal(user1, 10 ether);
        vm.deal(user2, 20 ether);

        vm.startPrank(user1);
        (bool success1, ) = address(xaaSwap).call{value: 5 ether}("");
        require(success1, "User1 claim failed");

        vm.stopPrank();

        vm.startPrank(user2);
        (bool success2, ) = address(xaaSwap).call{value: 10 ether}("");
        require(success2, "User2 claim failed");
        vm.stopPrank();

        // Fast forward to after the distribution period
        vm.warp(
            block.timestamp + DEPOSIT_PERIOD + DISTRIBUTION_START_DELAY + 1
        );

        // User1 claims rewards
        uint256 user1ExpectedReward = (5 ether * TOTAL_XAA_REWARD) / 15 ether;
        vm.startPrank(user1);
        xaaSwap.claimRewards();
        vm.stopPrank();

        assertEq(xaaToken.balanceOf(user1), user1ExpectedReward);
        assertTrue(xaaSwap.hasClaimed(user1));

        // User2 claims rewards
        uint256 user2ExpectedReward = (10 ether * TOTAL_XAA_REWARD) / 15 ether;
        vm.startPrank(user2);
        xaaSwap.claimRewards();
        vm.stopPrank();

        assertEq(xaaToken.balanceOf(user2), user2ExpectedReward);
        assertTrue(xaaSwap.hasClaimed(user2));
    }

    function testCannotClaimBeforeDistribution() public {
        vm.deal(user1, 10 ether);

        vm.startPrank(user1);
        (bool success1, ) = address(xaaSwap).call{value: 5 ether}("");
        require(success1, "User1 send dbc failed");
        vm.expectRevert("Distribution not started");
        xaaSwap.claimRewards();
        vm.stopPrank();
    }

    function testCannotDoubleClaim() public {
        vm.deal(user1, 10 ether);

        vm.startPrank(user1);
        (bool success1, ) = address(xaaSwap).call{value: 5 ether}("");
        require(success1, "User1 send dbc failed");
        vm.stopPrank();

        // Fast forward to after the distribution period
        vm.warp(
            block.timestamp + DEPOSIT_PERIOD + DISTRIBUTION_START_DELAY + 1
        );

        vm.startPrank(user1);
        xaaSwap.claimRewards();
        vm.expectRevert("Rewards already claimed");
        xaaSwap.claimRewards();
        vm.stopPrank();
    }

    function testSingleUserTakesAllRewards() public {
        vm.deal(user1, 10 ether);

        vm.startPrank(user1);
        (bool success, ) = address(xaaSwap).call{value: 10 ether}("");
        require(success, "Deposit failed");
        vm.stopPrank();

        // Fast forward to after the distribution period
        vm.warp(
            block.timestamp + DEPOSIT_PERIOD + DISTRIBUTION_START_DELAY + 1
        );

        uint256 expectedReward = TOTAL_XAA_REWARD;
        vm.startPrank(user1);
        xaaSwap.claimRewards();
        vm.stopPrank();

        assertEq(xaaToken.balanceOf(user1), expectedReward);
    }

    function testSmallDepositRewards() public {
        vm.deal(user1, 1 wei);

        vm.startPrank(user1);
        (bool success, ) = address(xaaSwap).call{value: 1 wei}("");
        require(success, "Deposit failed");
        vm.stopPrank();

        // Fast forward
        vm.warp(
            block.timestamp + DEPOSIT_PERIOD + DISTRIBUTION_START_DELAY + 1
        );

        uint256 expectedReward = (1 wei * TOTAL_XAA_REWARD) / 1 wei;
        vm.startPrank(user1);
        xaaSwap.claimRewards();
        vm.stopPrank();

        assertEq(xaaToken.balanceOf(user1), expectedReward);
    }

    function testMultipleDepositsBySameUser() public {
        vm.deal(user1, 10 ether);

        vm.startPrank(user1);
        (bool success1, ) = address(xaaSwap).call{value: 3 ether}("");
        require(success1, "First deposit failed");

        (bool success2, ) = address(xaaSwap).call{value: 2 ether}("");
        require(success2, "Second deposit failed");
        vm.stopPrank();

        assertEq(xaaSwap.userDeposits(user1), 5 ether);
        assertEq(xaaSwap.totalDepositedDBC(), 5 ether);
    }

    function testCannotDepositAfterPeriodEnds() public {
        vm.deal(user1, 10 ether);

        // Fast forward to after the deposit period
        vm.warp(block.timestamp + DEPOSIT_PERIOD + 1);

        vm.startPrank(user1);
        vm.expectRevert("Deposit period has ended");
        (bool success, ) = address(xaaSwap).call{value: 5 ether}("");
        require(!success, "Deposit should fail after period ends");
        vm.stopPrank();
    }

    function testClaimDBCSuccess() public {
        // Simulate deposits from a user
        vm.deal(user1, 10 ether);
        vm.prank(user1);
        (bool success, ) = address(xaaSwap).call{value: 10 ether}("");
        assertTrue(success);

        // Fast forward to after the deposit period
        vm.warp(block.timestamp + 15 days);

        // Owner claims the remaining DBC
        uint256 initialOwnerBalance = owner.balance;
        vm.prank(owner);
        xaaSwap.claimDBC();
        assertEq(owner.balance, initialOwnerBalance + 10 ether, "Owner should receive all remaining DBC");
    }

    function testClaimDBCFailsDuringDepositPeriod() public {
        // Simulate deposits from a user
        vm.deal(user1, 10 ether);
        vm.prank(user1);
        (bool success, ) = address(xaaSwap).call{value: 10 ether}("");
        assertTrue(success);

        // Attempt to claim DBC during the deposit period
        vm.prank(owner);
        vm.expectRevert("Distribution not started");
        xaaSwap.claimDBC();
    }

    function testClaimDBCFailsForNonOwner() public {
        // Simulate deposits from a user
        vm.deal(user1, 10 ether);
        vm.prank(user1);
        (bool success, ) = address(xaaSwap).call{value: 10 ether}("");
        assertTrue(success);

        // Fast forward to after the deposit period
        vm.warp(block.timestamp + 15 days);

        // Non-owner tries to claim DBC
        vm.prank(user1);
        vm.expectRevert();
        xaaSwap.claimDBC();
    }

    function testClaimDBCFailsWithNoBalance() public {
        // Fast forward to after the deposit period
        vm.warp(block.timestamp + 15 days);

        // Owner tries to claim DBC when there's no balance
        vm.prank(owner);
        vm.expectRevert("No DBC to claim");
        xaaSwap.claimDBC();
    }
}
