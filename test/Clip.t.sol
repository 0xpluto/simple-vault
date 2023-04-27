// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {Clip} from "../src/Clip.sol";
import {Utilities} from "./utils/Utilities.sol";

contract ClipTest is Test {
    Clip internal clip;
    Utilities internal utils;
    ERC20 internal usdc;

    address treasury;
    address team;
    address payable[] internal users;

    function setUp() public {
        utils = new Utilities();
        users = utils.createUsers(10);

        // The first user will be the treasury
        treasury = users[0];
        
        // The last user will be the team
        team = users[9];

        usdc = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
        deal(address(usdc), treasury, 5000e6);

        vm.prank(team);
        clip = new Clip(treasury, address(usdc));

        vm.prank(treasury);
        usdc.approve(address(clip), 5000e6);
    }

    function test_setUp() public {
        assertEq(clip.owner(), team);
        assertEq(usdc.balanceOf(treasury), 5000e6);
        assertEq(clip.TREASURY(), treasury);
    }

    function test_Clip_depositEth(uint256 amount) public {
        vm.assume(amount <= 20 ether);
        address user = users[1];
        uint currentPeriod = clip.currentReleasePeriod();

        vm.prank(user);
        clip.depositEth{value: amount}();

        assert(clip.releasePeriodBalances(user, currentPeriod) == amount);
        assert(clip.releasePeriodRewards(currentPeriod) == amount);
    }

    function test_Clip_fallback(uint256 amount) public {
        vm.assume(amount <= 20 ether);
        address user = users[1];
        uint currentPeriod = clip.currentReleasePeriod();

        vm.prank(user);
        (bool succes,) = payable(clip).call{gas: 1000000, value: amount}("");
        assert(succes);

        assert(clip.releasePeriodBalances(user, currentPeriod) == amount);
        assert(clip.releasePeriodRewards(currentPeriod) == amount);
    }

    function test_Clip_depositEth_TooMuchEth(uint256 amount) public {
        vm.assume(amount > 20 ether && amount < 10000 ether);
        address user = users[1];
        uint currentPeriod = clip.currentReleasePeriod();

        vm.prank(user);
        vm.expectRevert(Clip.TooMuchEth.selector);
        clip.depositEth{value: amount}();

        assert(clip.releasePeriodBalances(user, currentPeriod) == 0);
        assert(clip.releasePeriodRewards(currentPeriod) == 0);
    }

    function test_Clip_fallback_TooMuchEth(uint256 amount) public {
        vm.assume(amount > 20 ether && amount < 10000 ether);
        address user = users[1];
        uint currentPeriod = clip.currentReleasePeriod();

        vm.prank(user);
        (bool success,) = payable(clip).call{gas: 1000000, value: amount}("");
        assert(!success);

        assert(clip.releasePeriodBalances(user, currentPeriod) == 0);
        assert(clip.releasePeriodRewards(currentPeriod) == 0);
    }

    function test_Clip_releaseRewards_NotOwner(address user) public {
        vm.assume(user != team);

        vm.prank(user);
        vm.expectRevert("UNAUTHORIZED");
        clip.releaseRewards();
    }

    function test_Clip_releaseRewards_ReleaseNotReady() public {
        uint currentPeriod = clip.currentReleasePeriod();

        vm.prank(team);
        vm.expectRevert(Clip.ReleaseNotReady.selector);
        clip.releaseRewards();

        assertEq(clip.currentReleasePeriod(), currentPeriod);
        assertEq(usdc.balanceOf(address(clip)), 0);
        assertEq(usdc.balanceOf(treasury), 5000e6);
    }

    function test_Clip_releaseRewards() public {
        uint currentPeriod = clip.currentReleasePeriod();

        vm.warp(block.timestamp + 1 weeks);
        vm.prank(team);
        clip.releaseRewards();

        assertEq(clip.currentReleasePeriod(), currentPeriod + 1 weeks);
        assertEq(usdc.balanceOf(address(clip)), 1000e6);
        assertEq(usdc.balanceOf(treasury), 4000e6);
    }

    function test_Clip_claimRewards_1User(uint256 amount) public {
        vm.assume(amount <= 20 ether && amount > 0);
        address user = users[1];
        vm.prank(user);
        clip.depositEth{value: amount}();

        uint postDepositBalance = user.balance;

        uint currentPeriod = clip.currentReleasePeriod();

        releaseRewards();

        vm.prank(user);
        uint reward = clip.claimRewards(currentPeriod);

        assertEq(usdc.balanceOf(user), 1000e6);
        assertEq(reward, 1000e6);
        assertEq(usdc.balanceOf(address(clip)), 0);
        assertEq(postDepositBalance + amount, user.balance);
    }

    function test_Clip_claimRewards_2User(uint256 amount1, uint256 amount2) public {
        vm.assume(amount1 <= 20 ether && amount1 > 0);
        vm.assume(amount2 <= 20 ether && amount2 > 0);

        address user1 = users[1];
        address user2 = users[2];

        vm.prank(user1);
        clip.depositEth{value: amount1}();

        vm.prank(user2);
        clip.depositEth{value: amount2}();

        uint postDepositBalance1 = user1.balance;
        uint postDepositBalance2 = user2.balance;

        uint currentPeriod = clip.currentReleasePeriod();

        releaseRewards();

        vm.prank(user1);
        uint reward1 = clip.claimRewards(currentPeriod);

        vm.prank(user2);
        uint reward2 = clip.claimRewards(currentPeriod);

        assertLe(reward1 + reward2, 1000e6, "rewarded too much");
        assertApproxEqAbs(reward1 + reward2, 1000e6, 1, "Not enough rewarded");
        assertApproxEqAbs(usdc.balanceOf(address(clip)), 0, 1, "Left over usdc in clip");
        assertEq(postDepositBalance1 + amount1, user1.balance, "post claim user1 deposit");
        assertEq(postDepositBalance2 + amount2, user2.balance, "post claim user2 deposit");
    }

    function test_Clip_claimRewards_3User(uint256 amount1, uint256 amount2, uint256 amount3) public {
        vm.assume(amount1 <= 20 ether && amount1 > 0);
        vm.assume(amount2 <= 20 ether && amount2 > 0);
        vm.assume(amount3 <= 20 ether && amount3 > 0);

        address user1 = users[1];
        address user2 = users[2];
        address user3 = users[3];

        vm.prank(user1);
        clip.depositEth{value: amount1}();

        vm.prank(user2);
        clip.depositEth{value: amount2}();

        vm.prank(user3);
        clip.depositEth{value: amount3}();

        uint postDepositBalance1 = user1.balance;
        uint postDepositBalance2 = user2.balance;
        uint postDepositBalance3 = user3.balance;

        uint currentPeriod = clip.currentReleasePeriod();

        releaseRewards();

        vm.prank(user1);
        uint reward1 = clip.claimRewards(currentPeriod);

        vm.prank(user2);
        uint reward2 = clip.claimRewards(currentPeriod);

        vm.prank(user3);
        uint reward3 = clip.claimRewards(currentPeriod);

        assertLe(reward1 + reward2 + reward3, 1000e6, "rewarded too much");
        // The delta value will keep getting greater due to rounding with uint's
        // But user still gets their yield
        // Maximum delta will be # of users deposited - 1
        assertApproxEqAbs(reward1 + reward2 + reward3, 1000e6, 2, "Not enough rewarded");
        assertApproxEqAbs(usdc.balanceOf(address(clip)), 0, 2, "Left over usdc in clip");
        assertEq(postDepositBalance1 + amount1, user1.balance, "post claim user1 deposit");
        assertEq(postDepositBalance2 + amount2, user2.balance, "post claim user2 deposit");
        assertEq(postDepositBalance3 + amount3, user3.balance, "post claim user3 deposit");
    }

    function test_Clip_claimRewards_4User(uint256 amount1, uint256 amount2, uint256 amount3, uint256 amount4) public {
        vm.assume(amount1 <= 20 ether && amount1 > 0);
        vm.assume(amount2 <= 20 ether && amount2 > 0);
        vm.assume(amount3 <= 20 ether && amount3 > 0);
        vm.assume(amount4 <= 20 ether && amount4 > 0);

        address user1 = users[1];
        address user2 = users[2];
        address user3 = users[3];
        address user4 = users[4];

        vm.prank(user1);
        clip.depositEth{value: amount1}();

        vm.prank(user2);
        clip.depositEth{value: amount2}();

        vm.prank(user3);
        clip.depositEth{value: amount3}();

        vm.prank(user4);
        clip.depositEth{value: amount4}();

        uint postDepositBalance1 = user1.balance;
        uint postDepositBalance2 = user2.balance;
        uint postDepositBalance3 = user3.balance;
        uint postDepositBalance4 = user4.balance;

        uint currentPeriod = clip.currentReleasePeriod();

        releaseRewards();

        vm.prank(user1);
        uint reward1 = clip.claimRewards(currentPeriod);

        vm.prank(user2);
        uint reward2 = clip.claimRewards(currentPeriod);

        vm.prank(user3);
        uint reward3 = clip.claimRewards(currentPeriod);

        vm.prank(user4);
        uint reward4 = clip.claimRewards(currentPeriod);

        assertLe(reward1 + reward2 + reward3 + reward4, 1000e6, "rewarded too much");
        // The delta value will keep getting greater due to rounding with uint's
        // But user still gets their yield
        // Maximum delta will be # of users deposited - 1
        assertApproxEqAbs(reward1 + reward2 + reward3 + reward4, 1000e6, 3, "Not enough rewarded");
        assertApproxEqAbs(usdc.balanceOf(address(clip)), 0, 3, "Left over usdc in clip");
        assertEq(postDepositBalance1 + amount1, user1.balance, "post claim user1 deposit");
        assertEq(postDepositBalance2 + amount2, user2.balance, "post claim user2 deposit");
        assertEq(postDepositBalance3 + amount3, user3.balance, "post claim user3 deposit");
        assertEq(postDepositBalance4 + amount4, user4.balance, "post claim user4 deposit");
    }

    function releaseRewards() public {
        vm.warp(block.timestamp + 1 weeks);
        vm.prank(team);
        clip.releaseRewards();
    }
}
