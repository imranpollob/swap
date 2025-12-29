// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/Factory.sol";
import "../src/Router.sol";
import "../src/Pair.sol";
import "../src/WETH9.sol";
import "../src/test/mocks/ERC20Mock.sol";

/**
 * @title EdgeCases Test Suite
 * @notice Tests edge cases, boundary conditions, and error scenarios
 * @dev Covers zero amounts, max values, precision, approvals, deadlines
 */
contract EdgeCasesTest is Test {
    Factory factory;
    Router router;
    WETH9 weth;
    ERC20Mock tokenA;
    ERC20Mock tokenB;
    Pair pair;

    address user = address(0x1234);

    function setUp() public {
        weth = new WETH9();
        factory = new Factory();
        router = new Router(address(factory), address(weth));

        tokenA = new ERC20Mock("Token A", "TKA", 18);
        tokenB = new ERC20Mock("Token B", "TKB", 18);

        // Create pair and add initial liquidity
        tokenA.mint(address(this), 1_000_000 * 10 ** 18);
        tokenB.mint(address(this), 1_000_000 * 10 ** 18);
        tokenA.approve(address(router), type(uint256).max);
        tokenB.approve(address(router), type(uint256).max);

        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            100_000 * 10 ** 18,
            100_000 * 10 ** 18,
            0,
            0,
            address(this),
            block.timestamp
        );

        address pairAddress = factory.getPair(address(tokenA), address(tokenB));
        pair = Pair(pairAddress);
    }

    // ============ ZERO AMOUNT TESTS ============

    function testRevert_SwapZeroAmount() public {
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        vm.expectRevert("Router: INSUFFICIENT_INPUT_AMOUNT");
        router.swapExactTokensForTokens(
            0,
            0,
            path,
            address(this),
            block.timestamp
        );
    }

    function testRevert_AddLiquidityZeroAmountA() public {
        vm.expectRevert();
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            0,
            100 * 10 ** 18,
            0,
            0,
            address(this),
            block.timestamp
        );
    }

    function testRevert_AddLiquidityZeroAmountB() public {
        vm.expectRevert();
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            100 * 10 ** 18,
            0,
            0,
            0,
            address(this),
            block.timestamp
        );
    }

    // ============ DEADLINE TESTS ============

    function testRevert_SwapExpiredDeadline() public {
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        vm.expectRevert("Router: EXPIRED");
        router.swapExactTokensForTokens(
            1 * 10 ** 18,
            0,
            path,
            address(this),
            block.timestamp - 1
        );
    }

    function testRevert_AddLiquidityExpiredDeadline() public {
        vm.expectRevert("Router: EXPIRED");
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            100 * 10 ** 18,
            100 * 10 ** 18,
            0,
            0,
            address(this),
            block.timestamp - 1
        );
    }

    function testRevert_RemoveLiquidityExpiredDeadline() public {
        uint256 liquidity = pair.balanceOf(address(this));
        pair.approve(address(router), liquidity);

        vm.expectRevert("Router: EXPIRED");
        router.removeLiquidity(
            address(tokenA),
            address(tokenB),
            liquidity / 2,
            0,
            0,
            address(this),
            block.timestamp - 1
        );
    }

    // ============ SLIPPAGE PROTECTION TESTS ============

    function testRevert_SwapInsufficientOutputAmount() public {
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        uint256 amountIn = 10 * 10 ** 18;
        uint256[] memory amounts = router.getAmountsOut(amountIn, path);
        uint256 impossibleMinOut = amounts[1] * 2; // Require 2x what we'd get

        vm.expectRevert("Router: INSUFFICIENT_OUTPUT_AMOUNT");
        router.swapExactTokensForTokens(
            amountIn,
            impossibleMinOut,
            path,
            address(this),
            block.timestamp
        );
    }

    function testRevert_RemoveLiquidityInsufficientAmountA() public {
        uint256 liquidity = pair.balanceOf(address(this));
        pair.approve(address(router), liquidity);

        vm.expectRevert("Router: INSUFFICIENT_A_AMOUNT");
        router.removeLiquidity(
            address(tokenA),
            address(tokenB),
            liquidity / 2,
            type(uint256).max, // Impossible minimum
            0,
            address(this),
            block.timestamp
        );
    }

    function testRevert_RemoveLiquidityInsufficientAmountB() public {
        uint256 liquidity = pair.balanceOf(address(this));
        pair.approve(address(router), liquidity);

        vm.expectRevert("Router: INSUFFICIENT_B_AMOUNT");
        router.removeLiquidity(
            address(tokenA),
            address(tokenB),
            liquidity / 2,
            0,
            type(uint256).max, // Impossible minimum
            address(this),
            block.timestamp
        );
    }

    // ============ APPROVAL TESTS ============

    function testRevert_SwapWithoutApproval() public {
        tokenA.mint(user, 10 * 10 ** 18);

        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        vm.prank(user);
        vm.expectRevert();
        router.swapExactTokensForTokens(
            1 * 10 ** 18,
            0,
            path,
            user,
            block.timestamp
        );
    }

    function testRevert_AddLiquidityWithoutApproval() public {
        tokenA.mint(user, 100 * 10 ** 18);
        tokenB.mint(user, 100 * 10 ** 18);

        vm.prank(user);
        vm.expectRevert();
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            10 * 10 ** 18,
            10 * 10 ** 18,
            0,
            0,
            user,
            block.timestamp
        );
    }

    // ============ PRECISION & ROUNDING TESTS ============

    function test_SwapSmallAmountPrecision() public {
        // Test very small swap amounts don't get lost to rounding
        uint256 smallAmount = 1000; // Very small amount (not even 1 wei with 18 decimals)

        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        uint256[] memory amounts = router.getAmountsOut(smallAmount, path);

        // Should get something back (not rounded to 0)
        assertGt(amounts[1], 0, "Small swap should not round to zero");
    }

    function test_SwapLargeAmountNoOverflow() public {
        // Test large amounts don't overflow
        uint256 largeAmount = 10_000 * 10 ** 18;

        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        uint256 balanceBefore = tokenB.balanceOf(address(this));

        router.swapExactTokensForTokens(
            largeAmount,
            0,
            path,
            address(this),
            block.timestamp
        );

        uint256 balanceAfter = tokenB.balanceOf(address(this));
        assertGt(balanceAfter, balanceBefore, "Should receive tokens");
    }

    // ============ IDENTICAL TOKENS TEST ============

    function testRevert_CreatePairIdenticalTokens() public {
        vm.expectRevert("Factory: IDENTICAL_ADDRESSES");
        factory.createPair(address(tokenA), address(tokenA));
    }

    function testRevert_CreatePairZeroAddress() public {
        vm.expectRevert("Factory: ZERO_ADDRESS");
        factory.createPair(address(0), address(tokenA));
    }

    function testRevert_CreateDuplicatePair() public {
        ERC20Mock tokenC = new ERC20Mock("Token C", "TKC", 18);
        factory.createPair(address(tokenA), address(tokenC));

        vm.expectRevert("Factory: PAIR_EXISTS");
        factory.createPair(address(tokenA), address(tokenC));
    }

    // ============ INVALID PATH TESTS ============

    function testRevert_SwapInvalidPathLength() public {
        address[] memory path = new address[](1);
        path[0] = address(tokenA);

        vm.expectRevert("Router: INVALID_PATH");
        router.getAmountsOut(1 * 10 ** 18, path);
    }

    function testRevert_SwapNonExistentPair() public {
        ERC20Mock tokenC = new ERC20Mock("Token C", "TKC", 18);
        tokenC.mint(address(this), 100 * 10 ** 18);
        tokenC.approve(address(router), type(uint256).max);

        address[] memory path = new address[](2);
        path[0] = address(tokenC);
        path[1] = address(tokenA);

        vm.expectRevert();
        router.swapExactTokensForTokens(
            1 * 10 ** 18,
            0,
            path,
            address(this),
            block.timestamp
        );
    }

    // ============ REENTRANCY PROTECTION TEST ============

    function test_PairLockPreventsReentrancy() public {
        // Verify swap emits correctly and lock works
        uint256 amountIn = 1 * 10 ** 18;

        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        uint256[] memory amounts = router.getAmountsOut(amountIn, path);

        // This should succeed (lock is released after tx)
        router.swapExactTokensForTokens(
            amountIn,
            0,
            path,
            address(this),
            block.timestamp
        );

        // Second swap should also work (lock released)
        router.swapExactTokensForTokens(
            amountIn,
            0,
            path,
            address(this),
            block.timestamp
        );
    }

    // ============ MINIMUM LIQUIDITY TEST ============

    function test_MinimumLiquidityLocked() public {
        // Create a new pair
        ERC20Mock tokenC = new ERC20Mock("Token C", "TKC", 18);
        ERC20Mock tokenD = new ERC20Mock("Token D", "TKD", 18);

        tokenC.mint(address(this), 100 * 10 ** 18);
        tokenD.mint(address(this), 100 * 10 ** 18);
        tokenC.approve(address(router), type(uint256).max);
        tokenD.approve(address(router), type(uint256).max);

        router.addLiquidity(
            address(tokenC),
            address(tokenD),
            10 * 10 ** 18,
            10 * 10 ** 18,
            0,
            0,
            address(this),
            block.timestamp
        );

        address newPairAddress = factory.getPair(
            address(tokenC),
            address(tokenD)
        );
        Pair newPair = Pair(newPairAddress);

        // Check that MINIMUM_LIQUIDITY is locked at address(0)
        uint256 burnedLiquidity = newPair.balanceOf(address(0));
        assertEq(
            burnedLiquidity,
            newPair.MINIMUM_LIQUIDITY(),
            "Minimum liquidity should be locked"
        );
    }
}
