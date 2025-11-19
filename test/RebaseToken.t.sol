// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {Test, console} from "forge-std/Test.sol";
import {RebaseToken} from "../src/RebaseToken.sol";
import {Vault} from "../src/Vault.sol";
import {IRebaseToken} from "../src/interface/IRebaseToken.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

contract RebaseTokenTest is Test {
    RebaseToken private rebaseToken;
    Vault private vault;

    address public owner = makeAddr("owner");
    address public user = makeAddr("user");
    uint256 public SEND_VALUE = 1e5;

    // Setup function and test functions will follow
    function setUp() public {
        vm.startPrank(owner);

        rebaseToken = new RebaseToken();

        vault = new Vault(IRebaseToken(address(rebaseToken)));

        rebaseToken.grantMintAndBurnRole(address(vault));

        // (bool success, ) = payable(address(vault)).call{value: 1 ether}("");
        vm.stopPrank();
    }

    function addRewardsToVault(uint256 rewardAmount) public {
        // (bool success, ) = payable(address(vault)).call{value: rewardAmount}(
        //     ""
        // );
    }

    function testDepositLinear(uint256 amount) public {
        amount = bound(amount, 1e5, type(uint96).max);
        vm.startPrank(user);
        vm.deal(user, amount);
        vault.deposit{value: amount}();
        uint256 startBalance = rebaseToken.balanceOf(user);
        console.log("startBlance", startBalance);
        assertEq(startBalance, amount);
        vm.warp(block.timestamp + 1 hours);
        uint256 middleBalance = rebaseToken.balanceOf(user);
        assertGt(middleBalance, startBalance);
        vm.warp(block.timestamp + 1 hours);
        uint256 endBalance = rebaseToken.balanceOf(user);
        assertGt(endBalance, middleBalance);
        assertApproxEqAbs(
            endBalance - middleBalance,
            middleBalance - startBalance,
            1
        );
        vm.stopPrank();
    }

    function testRedeemAfterTimePassed(
        uint256 depositAmount,
        uint256 time
    ) public {
        time = bound(time, 1000, 365 days); // 可以限制在一年以内
        depositAmount = bound(depositAmount, 1e5, 1e24); // 不超过 1e24 wei
        // 2️⃣ 给用户足够 ETH
        vm.deal(user, depositAmount);
        // 3️⃣ 用户 deposit
        vm.prank(user);
        vault.deposit{value: depositAmount}();
        // 4️⃣ 时间流逝
        vm.warp(block.timestamp + time);
        // 5️⃣ 计算用户 token 增加量
        uint256 balanceAfterSomeTime = rebaseToken.balanceOf(user);
        // 6️⃣ 给 Vault 足够 ETH 支付 redeem
        uint256 rewardAmount = balanceAfterSomeTime - depositAmount;
        if (rewardAmount > 0) {
            vm.deal(owner, rewardAmount);
            vm.prank(owner);
            addRewardsToVault(rewardAmount);
        }

        // 7️⃣ 用户 redeem，但保证不会超过 Vault 余额
        uint256 redeemAmount = balanceAfterSomeTime;
        if (redeemAmount > address(vault).balance) {
            redeemAmount = address(vault).balance;
        }
        vm.prank(user);
        vault.redeem(redeemAmount);

        // 8️⃣ 断言用户最终 ETH >= deposit + reward
        uint256 ethBalance = address(user).balance;
        assertGt(ethBalance, depositAmount); // 用户至少拿回本金
        assertApproxEqAbs(ethBalance, balanceAfterSomeTime, 1); // 容忍 ±1 wei
    }

    function testTransfer(uint256 amount, uint256 amountToSend) public {
        // ------------------------------
        // 1️⃣ 安全限制初始存款
        // 确保用户余额至少可以发送一部分
        uint256 minSend = 1e5;
        amount = bound(amount, 2 * minSend, type(uint96).max); // 至少两倍 minSend，保证可发送

        // ------------------------------
        // 2️⃣ 安全计算可发送金额
        // 用户最多可以发送余额的一部分（amount - minSend）
        uint256 maxSend = amount - minSend;
        amountToSend = bound(amountToSend, minSend, maxSend); // 永远保证 max >= min

        // ------------------------------
        // 3️⃣ 给用户充值 ETH
        vm.deal(user, amount);
        vm.prank(user);
        vault.deposit{value: amount}();

        // ------------------------------
        // 4️⃣ 创建第二个用户并检查初始余额
        address userTwo = makeAddr("userTwo");
        uint256 userBalance = rebaseToken.balanceOf(user);
        uint256 userTwoBalance = rebaseToken.balanceOf(userTwo);
        assertEq(userBalance, amount);
        assertEq(userTwoBalance, 0);

        // ------------------------------
        // 5️⃣ 更新利率
        vm.prank(owner);
        rebaseToken.setInterestRate(4e10);

        // ------------------------------
        // 6️⃣ 用户向 userTwo 转账
        vm.prank(user);
        rebaseToken.transfer(userTwo, amountToSend);

        uint256 userBalanceAfterTransfer = rebaseToken.balanceOf(user);
        uint256 userTwoBalanceAfterTransfer = rebaseToken.balanceOf(userTwo);
        assertEq(userBalanceAfterTransfer, userBalance - amountToSend);
        assertEq(userTwoBalanceAfterTransfer, userTwoBalance + amountToSend);

        // ------------------------------
        // 7️⃣ warp 时间 1 天后检查利息增长
        vm.warp(block.timestamp + 1 days);

        uint256 userBalanceAfterWarp = rebaseToken.balanceOf(user);
        uint256 userTwoBalanceAfterWarp = rebaseToken.balanceOf(userTwo);

        // ------------------------------
        // 8️⃣ 检查利率逻辑
        uint256 userInterestRate = rebaseToken.getUserInterestRate(user);
        uint256 userTwoInterestRate = rebaseToken.getUserInterestRate(userTwo);
        assertEq(userInterestRate, 5e10); // 老用户利率保持之前
        assertEq(userTwoInterestRate, 5e10); // 新用户利率为当前

        // ------------------------------
        // 9️⃣ 检查利息是否增长
        assertGt(userBalanceAfterWarp, userBalanceAfterTransfer);
        assertGt(userTwoBalanceAfterWarp, userTwoBalanceAfterTransfer);
    }

    function testCannotSetInterestRate(uint256 newInterestRate) public {
        // Update the interest rate
        vm.prank(user);
        vm.expectRevert();
        rebaseToken.setInterestRate(newInterestRate);
    }

    function testCannotCallBurn() public {
        // Deposit funds
        vm.startPrank(user);
        vm.expectRevert();
        rebaseToken.burn(user, SEND_VALUE);
        vm.stopPrank();
    }

    function testCannotCallMint() public {
        // Deposit funds
        vm.startPrank(user);
        uint256 interestRate = rebaseToken.getInterestRate();
        vm.expectRevert();
        rebaseToken.mint(user, SEND_VALUE, interestRate);
        vm.stopPrank();
    }
}
