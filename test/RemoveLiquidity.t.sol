// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/Factory.sol";
import "../src/Router.sol";
import "../src/Pair.sol";
import "../src/WETH9.sol";
import "../src/test/mocks/ERC20Mock.sol";

/**
 * @title Remove Liquidity Test Suite
 * @notice Tests LP token lifecycle and liquidity removal scenarios
 * @dev Covers full/partial removal, fee accumulation, imbalanced removal
 */
contract RemoveLiquidityTest is Test {
    Factory factory;
    Router router;
    WETH9 weth;
    ERC20Mock tokenA;
    ERC20Mock tokenB;
    Pair pair;

    address lp1 = address(0x1111);
    address lp2 = address(0x2222);
    address trader = address(0x3333);

    function setUp() public {
        weth = new WETH9();
        factory = new Factory();
        router = new Router(address(factory), address(weth));

        tokenA = new ERC20Mock("Token A", "TKA", 18);
        tokenB = new ERC20Mock("Token B", "TKB", 18);

        // Mint to LPs and trader
        tokenA.mint(lp1, 1_000_000 * 10 ** 18);
        tokenB.mint(lp1, 1_000_000 * 10 ** 18);
        tokenA.mint(lp2, 1_000_000 * 10 ** 18);
        tokenB.mint(lp2, 1_000_000 * 10 ** 18);
        tokenA.mint(trader, 1_000_000 * 10 ** 18);
        tokenB.mint(trader, 1_000_000 * 10 ** 18);
    }

    function _setupPoolWithLP1() internal returns (uint256 liquidity) {
        vm.startPrank(lp1);
        tokenA.approve(address(router), type(uint256).max);
        tokenB.approve(address(router), type(uint256).max);

        (, , liquidity) = router.addLiquidity(
            address(tokenA),
            address(tokenB),
            10_000 * 10 ** 18,
            10_000 * 10 ** 18,
            0,
            0,
            lp1,
            block.timestamp
        );
        vm.stopPrank();

        address pairAddress = factory.getPair(address(tokenA), address(tokenB));
        pair = Pair(pairAddress);
    }

    // ============ FULL REMOVAL TESTS ============

    function test_RemoveLiquidity_FullPosition() public {
        uint256 lpBalance = _setupPoolWithLP1();

        uint256 tokenABefore = tokenA.balanceOf(lp1);
        uint256 tokenBBefore = tokenB.balanceOf(lp1);

        vm.startPrank(lp1);
        pair.approve(address(router), lpBalance);

        (uint256 amountA, uint256 amountB) = router.removeLiquidity(
            address(tokenA),
            address(tokenB),
            lpBalance,
            0,
            0,
            lp1,
            block.timestamp
        );
        vm.stopPrank();

        // Should get back approximately initial deposit (minus MINIMUM_LIQUIDITY)
        assertGt(amountA, 0, "Should receive tokenA");
        assertGt(amountB, 0, "Should receive tokenB");
        assertEq(
            pair.balanceOf(lp1),
            0,
            "LP should have no remaining LP tokens"
        );
        assertEq(
            tokenA.balanceOf(lp1),
            tokenABefore + amountA,
            "TokenA balance should increase"
        );
        assertEq(
            tokenB.balanceOf(lp1),
            tokenBBefore + amountB,
            "TokenB balance should increase"
        );
    }

    // ============ PARTIAL REMOVAL TESTS ============

    function test_RemoveLiquidity_PartialPosition() public {
        uint256 lpBalance = _setupPoolWithLP1();
        uint256 removeAmount = lpBalance / 2;

        vm.startPrank(lp1);
        pair.approve(address(router), removeAmount);

        uint256 lpBefore = pair.balanceOf(lp1);

        (uint256 amountA, uint256 amountB) = router.removeLiquidity(
            address(tokenA),
            address(tokenB),
            removeAmount,
            0,
            0,
            lp1,
            block.timestamp
        );
        vm.stopPrank();

        // Should have half LP tokens remaining
        assertEq(
            pair.balanceOf(lp1),
            lpBefore - removeAmount,
            "Should have half LP remaining"
        );
        assertGt(amountA, 0, "Should receive tokenA");
        assertGt(amountB, 0, "Should receive tokenB");
    }

    function test_RemoveLiquidity_MultiplePartialRemovals() public {
        uint256 lpBalance = _setupPoolWithLP1();
        uint256 removePerTx = lpBalance / 4;

        vm.startPrank(lp1);
        pair.approve(address(router), type(uint256).max);

        uint256 totalA = 0;
        uint256 totalB = 0;

        // Remove in 4 chunks
        for (uint i = 0; i < 4; i++) {
            (uint256 amountA, uint256 amountB) = router.removeLiquidity(
                address(tokenA),
                address(tokenB),
                removePerTx,
                0,
                0,
                lp1,
                block.timestamp
            );
            totalA += amountA;
            totalB += amountB;
        }
        vm.stopPrank();

        assertEq(pair.balanceOf(lp1), 0, "All LP should be removed");
        assertGt(totalA, 0, "Should have received tokenA");
        assertGt(totalB, 0, "Should have received tokenB");
    }

    // ============ FEE ACCUMULATION TESTS ============

    function test_RemoveLiquidity_AfterSwaps_FeeAccumulation() public {
        uint256 lpBalance = _setupPoolWithLP1();

        // Get initial values
        (uint112 reserve0Pre, uint112 reserve1Pre, ) = pair.getReserves();
        uint256 kPre = uint256(reserve0Pre) * uint256(reserve1Pre);

        // Trader performs swaps (generates fees)
        vm.startPrank(trader);
        tokenA.approve(address(router), type(uint256).max);
        tokenB.approve(address(router), type(uint256).max);

        address[] memory pathAtoB = new address[](2);
        pathAtoB[0] = address(tokenA);
        pathAtoB[1] = address(tokenB);

        address[] memory pathBtoA = new address[](2);
        pathBtoA[0] = address(tokenB);
        pathBtoA[1] = address(tokenA);

        // Multiple swaps to accumulate fees
        for (uint i = 0; i < 10; i++) {
            router.swapExactTokensForTokens(
                100 * 10 ** 18,
                0,
                pathAtoB,
                trader,
                block.timestamp
            );
            router.swapExactTokensForTokens(
                100 * 10 ** 18,
                0,
                pathBtoA,
                trader,
                block.timestamp
            );
        }
        vm.stopPrank();

        // K should have increased from fees
        (uint112 reserve0Post, uint112 reserve1Post, ) = pair.getReserves();
        uint256 kPost = uint256(reserve0Post) * uint256(reserve1Post);
        assertGt(kPost, kPre, "K should increase from fees");

        // LP removes liquidity
        vm.startPrank(lp1);
        pair.approve(address(router), lpBalance);

        (uint256 amountA, uint256 amountB) = router.removeLiquidity(
            address(tokenA),
            address(tokenB),
            lpBalance,
            0,
            0,
            lp1,
            block.timestamp
        );
        vm.stopPrank();

        // LP should get more than initial due to fees (accounting for MINIMUM_LIQUIDITY)
        // Note: Due to MINIMUM_LIQUIDITY lock, exact comparison is tricky
        // But we can verify amounts are substantial
        assertGt(
            amountA,
            9_900 * 10 ** 18,
            "Should get back substantial tokenA"
        );
        assertGt(
            amountB,
            9_900 * 10 ** 18,
            "Should get back substantial tokenB"
        );
    }

    // ============ MULTIPLE LP TESTS ============

    function test_RemoveLiquidity_MultipleProviders() public {
        // LP1 provides first
        vm.startPrank(lp1);
        tokenA.approve(address(router), type(uint256).max);
        tokenB.approve(address(router), type(uint256).max);
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            10_000 * 10 ** 18,
            10_000 * 10 ** 18,
            0,
            0,
            lp1,
            block.timestamp
        );
        vm.stopPrank();

        address pairAddress = factory.getPair(address(tokenA), address(tokenB));
        pair = Pair(pairAddress);

        uint256 lp1Balance = pair.balanceOf(lp1);

        // LP2 provides second
        vm.startPrank(lp2);
        tokenA.approve(address(router), type(uint256).max);
        tokenB.approve(address(router), type(uint256).max);
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            5_000 * 10 ** 18,
            5_000 * 10 ** 18,
            0,
            0,
            lp2,
            block.timestamp
        );
        vm.stopPrank();

        uint256 lp2Balance = pair.balanceOf(lp2);

        // LP2 should have ~half the LP tokens of LP1
        assertApproxEqRel(
            lp2Balance,
            lp1Balance / 2,
            0.01e18,
            "LP2 should have half LP1's tokens"
        );

        // Both remove liquidity
        vm.startPrank(lp1);
        pair.approve(address(router), lp1Balance);
        (uint256 amount1A, uint256 amount1B) = router.removeLiquidity(
            address(tokenA),
            address(tokenB),
            lp1Balance,
            0,
            0,
            lp1,
            block.timestamp
        );
        vm.stopPrank();

        vm.startPrank(lp2);
        pair.approve(address(router), lp2Balance);
        (uint256 amount2A, uint256 amount2B) = router.removeLiquidity(
            address(tokenA),
            address(tokenB),
            lp2Balance,
            0,
            0,
            lp2,
            block.timestamp
        );
        vm.stopPrank();

        // LP1 should get ~2x what LP2 gets
        assertApproxEqRel(
            amount1A,
            amount2A * 2,
            0.01e18,
            "LP1 should get ~2x tokenA"
        );
        assertApproxEqRel(
            amount1B,
            amount2B * 2,
            0.01e18,
            "LP1 should get ~2x tokenB"
        );
    }

    // ============ IMBALANCED POOL REMOVAL ============

    function test_RemoveLiquidity_FromImbalancedPool() public {
        uint256 lpBalance = _setupPoolWithLP1();

        // Make pool imbalanced via large swap
        vm.startPrank(trader);
        tokenA.approve(address(router), type(uint256).max);

        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        router.swapExactTokensForTokens(
            5_000 * 10 ** 18,
            0,
            path,
            trader,
            block.timestamp
        );
        vm.stopPrank();

        // Check pool is imbalanced
        (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();
        assertGt(reserve0, reserve1, "Pool should be imbalanced");

        // LP removes liquidity
        vm.startPrank(lp1);
        pair.approve(address(router), lpBalance);

        (uint256 amountA, uint256 amountB) = router.removeLiquidity(
            address(tokenA),
            address(tokenB),
            lpBalance,
            0,
            0,
            lp1,
            block.timestamp
        );
        vm.stopPrank();

        // LP should receive proportional to current reserves (more A, less B)
        assertGt(amountA, amountB, "Should receive more of abundant token");
    }

    // ============ MINIMUM AMOUNTS TESTS ============

    function test_RemoveLiquidity_WithMinimumAmounts() public {
        uint256 lpBalance = _setupPoolWithLP1();
        uint256 removeAmount = lpBalance / 2;

        // Calculate expected amounts
        (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();
        uint256 totalSupply = pair.totalSupply();

        // Determine which token is which
        address token0 = pair.token0();
        uint256 expectedA;
        uint256 expectedB;
        if (token0 == address(tokenA)) {
            expectedA = (removeAmount * reserve0) / totalSupply;
            expectedB = (removeAmount * reserve1) / totalSupply;
        } else {
            expectedB = (removeAmount * reserve0) / totalSupply;
            expectedA = (removeAmount * reserve1) / totalSupply;
        }

        vm.startPrank(lp1);
        pair.approve(address(router), removeAmount);

        // Should succeed with correct minimum amounts
        (uint256 amountA, uint256 amountB) = router.removeLiquidity(
            address(tokenA),
            address(tokenB),
            removeAmount,
            expectedA - 1, // Slightly below expected
            expectedB - 1,
            lp1,
            block.timestamp
        );
        vm.stopPrank();

        assertEq(amountA, expectedA, "Should get expected tokenA");
        assertEq(amountB, expectedB, "Should get expected tokenB");
    }

    // ============ EDGE CASE: REMOVE TO DIFFERENT ADDRESS ============

    function test_RemoveLiquidity_ToDifferentRecipient() public {
        uint256 lpBalance = _setupPoolWithLP1();
        address recipient = address(0xBEEF);

        uint256 recipientABefore = tokenA.balanceOf(recipient);
        uint256 recipientBBefore = tokenB.balanceOf(recipient);

        vm.startPrank(lp1);
        pair.approve(address(router), lpBalance);

        (uint256 amountA, uint256 amountB) = router.removeLiquidity(
            address(tokenA),
            address(tokenB),
            lpBalance,
            0,
            0,
            recipient, // Different recipient
            block.timestamp
        );
        vm.stopPrank();

        assertEq(
            tokenA.balanceOf(recipient),
            recipientABefore + amountA,
            "Recipient should receive tokenA"
        );
        assertEq(
            tokenB.balanceOf(recipient),
            recipientBBefore + amountB,
            "Recipient should receive tokenB"
        );
        assertEq(pair.balanceOf(lp1), 0, "LP should have no LP tokens");
    }

    // ============ GAS OPTIMIZATION TEST ============

    function test_RemoveLiquidity_GasUsage() public {
        uint256 lpBalance = _setupPoolWithLP1();

        vm.startPrank(lp1);
        pair.approve(address(router), lpBalance);

        uint256 gasStart = gasleft();
        router.removeLiquidity(
            address(tokenA),
            address(tokenB),
            lpBalance,
            0,
            0,
            lp1,
            block.timestamp
        );
        uint256 gasUsed = gasStart - gasleft();
        vm.stopPrank();

        // Log gas usage for optimization tracking
        emit log_named_uint("Gas used for removeLiquidity", gasUsed);
        assertLt(gasUsed, 200_000, "Gas should be reasonable");
    }
}
