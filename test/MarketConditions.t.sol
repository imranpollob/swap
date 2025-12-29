// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/Factory.sol";
import "../src/Router.sol";
import "../src/Pair.sol";
import "../src/WETH9.sol";
import "../src/test/mocks/ERC20Mock.sol";

/**
 * @title Market Conditions Test Suite
 * @notice Tests real-world market scenarios and conditions
 * @dev Covers high slippage, low liquidity, price impact, imbalanced pools, sandwich attacks
 */
contract MarketConditionsTest is Test {
    Factory factory;
    Router router;
    WETH9 weth;
    ERC20Mock tokenA;
    ERC20Mock tokenB;
    Pair pair;

    address alice = address(0x1111);
    address bob = address(0x2222);
    address attacker = address(0x3333);

    function setUp() public {
        weth = new WETH9();
        factory = new Factory();
        router = new Router(address(factory), address(weth));

        tokenA = new ERC20Mock("Token A", "TKA", 18);
        tokenB = new ERC20Mock("Token B", "TKB", 18);

        // Mint to test users
        tokenA.mint(alice, 1_000_000 * 10 ** 18);
        tokenB.mint(alice, 1_000_000 * 10 ** 18);
        tokenA.mint(bob, 1_000_000 * 10 ** 18);
        tokenB.mint(bob, 1_000_000 * 10 ** 18);
        tokenA.mint(attacker, 10_000_000 * 10 ** 18);
        tokenB.mint(attacker, 10_000_000 * 10 ** 18);
    }

    // ============ HIGH SLIPPAGE ENVIRONMENT ============

    function test_HighSlippage_LargeTradeInSmallPool() public {
        // Create small liquidity pool
        tokenA.mint(address(this), 1000 * 10 ** 18);
        tokenB.mint(address(this), 1000 * 10 ** 18);
        tokenA.approve(address(router), type(uint256).max);
        tokenB.approve(address(router), type(uint256).max);

        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            100 * 10 ** 18, // Small pool: 100 tokens each
            100 * 10 ** 18,
            0,
            0,
            address(this),
            block.timestamp
        );

        // Large trade relative to pool size
        uint256 largeSwap = 50 * 10 ** 18; // 50% of pool

        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        uint256[] memory amounts = router.getAmountsOut(largeSwap, path);

        // Calculate price impact
        uint256 idealOutput = largeSwap; // In 1:1 pool, ideal would be equal
        uint256 actualOutput = amounts[1];
        uint256 priceImpact = ((idealOutput - actualOutput) * 100) /
            idealOutput;

        // High slippage expected (should be >30% impact for 50% pool trade)
        assertGt(
            priceImpact,
            30,
            "Large trade should have significant price impact"
        );

        // Trade should still work
        router.swapExactTokensForTokens(
            largeSwap,
            0, // Accept any slippage for test
            path,
            address(this),
            block.timestamp
        );
    }

    // ============ LOW LIQUIDITY SCENARIOS ============

    function test_LowLiquidity_MinimumViablePool() public {
        // Create pool with minimum viable liquidity
        tokenA.mint(address(this), 10000);
        tokenB.mint(address(this), 10000);
        tokenA.approve(address(router), type(uint256).max);
        tokenB.approve(address(router), type(uint256).max);

        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            2000, // Just above MINIMUM_LIQUIDITY (1000)
            2000,
            0,
            0,
            address(this),
            block.timestamp
        );

        address pairAddress = factory.getPair(address(tokenA), address(tokenB));
        pair = Pair(pairAddress);

        (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();
        assertGt(reserve0, 0, "Reserve0 should be positive");
        assertGt(reserve1, 0, "Reserve1 should be positive");
    }

    function test_LowLiquidity_SwapDrainsPool() public {
        // Create small pool
        tokenA.mint(address(this), 10000 * 10 ** 18);
        tokenB.mint(address(this), 10000 * 10 ** 18);
        tokenA.approve(address(router), type(uint256).max);
        tokenB.approve(address(router), type(uint256).max);

        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            100 * 10 ** 18,
            100 * 10 ** 18,
            0,
            0,
            address(this),
            block.timestamp
        );

        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        // Try to get more output than reserve
        uint256 hugeSwap = 1000 * 10 ** 18;
        uint256[] memory amounts = router.getAmountsOut(hugeSwap, path);

        // Output should be capped below total reserve
        assertLt(amounts[1], 100 * 10 ** 18, "Output cannot exceed reserve");
    }

    // ============ PRICE IMPACT TESTS ============

    function test_PriceImpact_GradualIncrease() public {
        // Create balanced pool
        tokenA.mint(address(this), 1_000_000 * 10 ** 18);
        tokenB.mint(address(this), 1_000_000 * 10 ** 18);
        tokenA.approve(address(router), type(uint256).max);
        tokenB.approve(address(router), type(uint256).max);

        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            10_000 * 10 ** 18,
            10_000 * 10 ** 18,
            0,
            0,
            address(this),
            block.timestamp
        );

        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        // Test increasing trade sizes
        uint256[4] memory tradeSizes = [
            uint256(10 * 10 ** 18), // 0.1% of pool
            uint256(100 * 10 ** 18), // 1% of pool
            uint256(500 * 10 ** 18), // 5% of pool
            uint256(1000 * 10 ** 18) // 10% of pool
        ];

        uint256 lastImpact = 0;
        for (uint i = 0; i < tradeSizes.length; i++) {
            uint256[] memory amounts = router.getAmountsOut(
                tradeSizes[i],
                path
            );
            uint256 idealOutput = tradeSizes[i]; // 1:1 pool
            uint256 actualOutput = amounts[1];
            uint256 impact = ((idealOutput - actualOutput) * 10000) /
                idealOutput; // basis points

            // Price impact should increase with trade size
            assertGt(
                impact,
                lastImpact,
                "Larger trades should have higher impact"
            );
            lastImpact = impact;
        }
    }

    // ============ IMBALANCED POOL TESTS ============

    function test_ImbalancedPool_Extreme99to1Ratio() public {
        tokenA.mint(address(this), 1_000_000 * 10 ** 18);
        tokenB.mint(address(this), 1_000_000 * 10 ** 18);
        tokenA.approve(address(router), type(uint256).max);
        tokenB.approve(address(router), type(uint256).max);

        // Create extremely imbalanced pool (99:1)
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            9900 * 10 ** 18, // 99 parts
            100 * 10 ** 18, // 1 part
            0,
            0,
            address(this),
            block.timestamp
        );

        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        // Swap A for B (plenty of A, scarce B)
        uint256[] memory amounts = router.getAmountsOut(100 * 10 ** 18, path);

        // B should be much more valuable than A
        assertLt(
            amounts[1],
            10 * 10 ** 18,
            "Scarce token B should have high price"
        );

        // Swap should work
        router.swapExactTokensForTokens(
            100 * 10 ** 18,
            0,
            path,
            address(this),
            block.timestamp
        );
    }

    function test_ImbalancedPool_ArbitrageOpportunity() public {
        tokenA.mint(address(this), 1_000_000 * 10 ** 18);
        tokenB.mint(address(this), 1_000_000 * 10 ** 18);
        tokenA.approve(address(router), type(uint256).max);
        tokenB.approve(address(router), type(uint256).max);

        // Create imbalanced pool
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            1000 * 10 ** 18,
            100 * 10 ** 18,
            0,
            0,
            address(this),
            block.timestamp
        );

        address pairAddress = factory.getPair(address(tokenA), address(tokenB));
        pair = Pair(pairAddress);

        (uint112 reserve0Pre, uint112 reserve1Pre, ) = pair.getReserves();
        uint256 kPre = uint256(reserve0Pre) * uint256(reserve1Pre);

        // Arbitrageur swaps to extract value
        address[] memory path = new address[](2);
        path[0] = address(tokenB);
        path[1] = address(tokenA);

        router.swapExactTokensForTokens(
            50 * 10 ** 18,
            0,
            path,
            address(this),
            block.timestamp
        );

        (uint112 reserve0Post, uint112 reserve1Post, ) = pair.getReserves();
        uint256 kPost = uint256(reserve0Post) * uint256(reserve1Post);

        // K should increase (fees collected)
        assertGt(kPost, kPre, "K should increase after swap (fees)");
    }

    // ============ SANDWICH ATTACK SIMULATION ============

    function test_SandwichAttack_VictimGetsLess() public {
        tokenA.mint(address(this), 1_000_000 * 10 ** 18);
        tokenB.mint(address(this), 1_000_000 * 10 ** 18);
        tokenA.approve(address(router), type(uint256).max);
        tokenB.approve(address(router), type(uint256).max);

        // Create pool
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            10_000 * 10 ** 18,
            10_000 * 10 ** 18,
            0,
            0,
            address(this),
            block.timestamp
        );

        address[] memory pathAtoB = new address[](2);
        pathAtoB[0] = address(tokenA);
        pathAtoB[1] = address(tokenB);

        // Calculate what victim would get without attack
        uint256 victimAmount = 100 * 10 ** 18;
        uint256[] memory fairAmounts = router.getAmountsOut(
            victimAmount,
            pathAtoB
        );
        uint256 fairOutput = fairAmounts[1];

        // ATTACKER FRONT-RUNS: Buy B before victim
        vm.startPrank(attacker);
        tokenA.approve(address(router), type(uint256).max);
        router.swapExactTokensForTokens(
            500 * 10 ** 18, // Large front-run
            0,
            pathAtoB,
            attacker,
            block.timestamp
        );
        vm.stopPrank();

        // VICTIM SWAPS: Gets worse price due to front-run
        vm.startPrank(alice);
        tokenA.approve(address(router), type(uint256).max);
        uint256 aliceBalanceBefore = tokenB.balanceOf(alice);
        router.swapExactTokensForTokens(
            victimAmount,
            0, // No slippage protection (vulnerable)
            pathAtoB,
            alice,
            block.timestamp
        );
        uint256 victimActualOutput = tokenB.balanceOf(alice) -
            aliceBalanceBefore;
        vm.stopPrank();

        // ATTACKER BACK-RUNS: Sell B back
        address[] memory pathBtoA = new address[](2);
        pathBtoA[0] = address(tokenB);
        pathBtoA[1] = address(tokenA);

        vm.startPrank(attacker);
        tokenB.approve(address(router), type(uint256).max);
        router.swapExactTokensForTokens(
            tokenB.balanceOf(attacker),
            0,
            pathBtoA,
            attacker,
            block.timestamp
        );
        vm.stopPrank();

        // Victim got less than fair value
        assertLt(
            victimActualOutput,
            fairOutput,
            "Victim should get less due to sandwich"
        );
    }

    function test_SandwichProtection_SlippageLimit() public {
        tokenA.mint(address(this), 1_000_000 * 10 ** 18);
        tokenB.mint(address(this), 1_000_000 * 10 ** 18);
        tokenA.approve(address(router), type(uint256).max);
        tokenB.approve(address(router), type(uint256).max);

        // Create pool
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            10_000 * 10 ** 18,
            10_000 * 10 ** 18,
            0,
            0,
            address(this),
            block.timestamp
        );

        address[] memory pathAtoB = new address[](2);
        pathAtoB[0] = address(tokenA);
        pathAtoB[1] = address(tokenB);

        // Calculate fair price
        uint256 victimAmount = 100 * 10 ** 18;
        uint256[] memory fairAmounts = router.getAmountsOut(
            victimAmount,
            pathAtoB
        );
        uint256 minOut = (fairAmounts[1] * 99) / 100; // 1% slippage tolerance

        // ATTACKER FRONT-RUNS
        vm.startPrank(attacker);
        tokenA.approve(address(router), type(uint256).max);
        router.swapExactTokensForTokens(
            500 * 10 ** 18,
            0,
            pathAtoB,
            attacker,
            block.timestamp
        );
        vm.stopPrank();

        // VICTIM SWAPS WITH PROTECTION: Should revert due to slippage
        vm.startPrank(alice);
        tokenA.approve(address(router), type(uint256).max);
        vm.expectRevert("Router: INSUFFICIENT_OUTPUT_AMOUNT");
        router.swapExactTokensForTokens(
            victimAmount,
            minOut, // Protected by slippage limit
            pathAtoB,
            alice,
            block.timestamp
        );
        vm.stopPrank();
    }

    // ============ CONSECUTIVE SWAPS TEST ============

    function test_ConsecutiveSwaps_PriceChange() public {
        tokenA.mint(address(this), 1_000_000 * 10 ** 18);
        tokenB.mint(address(this), 1_000_000 * 10 ** 18);
        tokenA.approve(address(router), type(uint256).max);
        tokenB.approve(address(router), type(uint256).max);

        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            10_000 * 10 ** 18,
            10_000 * 10 ** 18,
            0,
            0,
            address(this),
            block.timestamp
        );

        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        uint256 swapAmount = 100 * 10 ** 18;

        // First swap
        uint256[] memory amounts1 = router.getAmountsOut(swapAmount, path);
        router.swapExactTokensForTokens(
            swapAmount,
            0,
            path,
            address(this),
            block.timestamp
        );

        // Second swap (same direction)
        uint256[] memory amounts2 = router.getAmountsOut(swapAmount, path);
        router.swapExactTokensForTokens(
            swapAmount,
            0,
            path,
            address(this),
            block.timestamp
        );

        // Third swap
        uint256[] memory amounts3 = router.getAmountsOut(swapAmount, path);

        // Each consecutive swap should yield less (price moves against trader)
        assertLt(amounts2[1], amounts1[1], "Second swap should yield less");
        assertLt(amounts3[1], amounts2[1], "Third swap should yield even less");
    }

    // ============ VOLATILITY TEST ============

    function test_Volatility_RapidBidirectionalSwaps() public {
        tokenA.mint(address(this), 1_000_000 * 10 ** 18);
        tokenB.mint(address(this), 1_000_000 * 10 ** 18);
        tokenA.approve(address(router), type(uint256).max);
        tokenB.approve(address(router), type(uint256).max);

        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            10_000 * 10 ** 18,
            10_000 * 10 ** 18,
            0,
            0,
            address(this),
            block.timestamp
        );

        address pairAddress = factory.getPair(address(tokenA), address(tokenB));
        pair = Pair(pairAddress);

        (uint112 r0Initial, uint112 r1Initial, ) = pair.getReserves();
        uint256 kInitial = uint256(r0Initial) * uint256(r1Initial);

        address[] memory pathAtoB = new address[](2);
        pathAtoB[0] = address(tokenA);
        pathAtoB[1] = address(tokenB);

        address[] memory pathBtoA = new address[](2);
        pathBtoA[0] = address(tokenB);
        pathBtoA[1] = address(tokenA);

        // Simulate volatile trading
        for (uint i = 0; i < 10; i++) {
            router.swapExactTokensForTokens(
                100 * 10 ** 18,
                0,
                pathAtoB,
                address(this),
                block.timestamp
            );
            router.swapExactTokensForTokens(
                100 * 10 ** 18,
                0,
                pathBtoA,
                address(this),
                block.timestamp
            );
        }

        (uint112 r0Final, uint112 r1Final, ) = pair.getReserves();
        uint256 kFinal = uint256(r0Final) * uint256(r1Final);

        // K should increase (fees accumulated)
        assertGt(kFinal, kInitial, "K should grow from fees during volatility");
    }
}
