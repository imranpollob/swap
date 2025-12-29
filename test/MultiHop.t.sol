// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/Factory.sol";
import "../src/Router.sol";
import "../src/Pair.sol";
import "../src/WETH9.sol";
import "../src/test/mocks/ERC20Mock.sol";

/**
 * @title Multi-Hop Routing Test Suite
 * @notice Tests multi-hop swap paths through multiple pools
 * @dev Covers 3-token paths, path efficiency, complex routing
 */
contract MultiHopTest is Test {
    Factory factory;
    Router router;
    WETH9 weth;
    ERC20Mock tokenA;
    ERC20Mock tokenB;
    ERC20Mock tokenC;
    ERC20Mock tokenD;

    function setUp() public {
        weth = new WETH9();
        factory = new Factory();
        router = new Router(address(factory), address(weth));

        tokenA = new ERC20Mock("Token A", "TKA", 18);
        tokenB = new ERC20Mock("Token B", "TKB", 18);
        tokenC = new ERC20Mock("Token C", "TKC", 18);
        tokenD = new ERC20Mock("Token D", "TKD", 18);

        // Mint tokens
        tokenA.mint(address(this), 10_000_000 * 10 ** 18);
        tokenB.mint(address(this), 10_000_000 * 10 ** 18);
        tokenC.mint(address(this), 10_000_000 * 10 ** 18);
        tokenD.mint(address(this), 10_000_000 * 10 ** 18);

        // Approvals
        tokenA.approve(address(router), type(uint256).max);
        tokenB.approve(address(router), type(uint256).max);
        tokenC.approve(address(router), type(uint256).max);
        tokenD.approve(address(router), type(uint256).max);
    }

    function _createBalancedPools() internal {
        // Create A-B pool (1:1)
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

        // Create B-C pool (1:1)
        router.addLiquidity(
            address(tokenB),
            address(tokenC),
            100_000 * 10 ** 18,
            100_000 * 10 ** 18,
            0,
            0,
            address(this),
            block.timestamp
        );

        // Create C-D pool (1:1)
        router.addLiquidity(
            address(tokenC),
            address(tokenD),
            100_000 * 10 ** 18,
            100_000 * 10 ** 18,
            0,
            0,
            address(this),
            block.timestamp
        );

        // Create A-C pool (direct route)
        router.addLiquidity(
            address(tokenA),
            address(tokenC),
            100_000 * 10 ** 18,
            100_000 * 10 ** 18,
            0,
            0,
            address(this),
            block.timestamp
        );
    }

    // ============ 3-TOKEN PATH TESTS ============

    function test_MultiHop_ThreeTokenPath() public {
        _createBalancedPools();

        // Swap A -> B -> C
        address[] memory path = new address[](3);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        path[2] = address(tokenC);

        uint256 amountIn = 1000 * 10 ** 18;
        uint256[] memory amounts = router.getAmountsOut(amountIn, path);

        uint256 balanceBefore = tokenC.balanceOf(address(this));

        router.swapExactTokensForTokens(
            amountIn,
            0,
            path,
            address(this),
            block.timestamp
        );

        uint256 balanceAfter = tokenC.balanceOf(address(this));

        assertEq(
            balanceAfter - balanceBefore,
            amounts[2],
            "Should receive expected amount"
        );
        assertGt(amounts[2], 0, "Should receive tokens");
    }

    function test_MultiHop_FourTokenPath() public {
        _createBalancedPools();

        // Swap A -> B -> C -> D
        address[] memory path = new address[](4);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        path[2] = address(tokenC);
        path[3] = address(tokenD);

        uint256 amountIn = 1000 * 10 ** 18;
        uint256[] memory amounts = router.getAmountsOut(amountIn, path);

        uint256 balanceBefore = tokenD.balanceOf(address(this));

        router.swapExactTokensForTokens(
            amountIn,
            0,
            path,
            address(this),
            block.timestamp
        );

        uint256 balanceAfter = tokenD.balanceOf(address(this));

        assertEq(
            balanceAfter - balanceBefore,
            amounts[3],
            "Should receive expected amount"
        );
    }

    // ============ PATH EFFICIENCY TESTS ============

    function test_MultiHop_DirectVsIndirectPath() public {
        _createBalancedPools();

        uint256 amountIn = 1000 * 10 ** 18;

        // Direct path: A -> C
        address[] memory directPath = new address[](2);
        directPath[0] = address(tokenA);
        directPath[1] = address(tokenC);
        uint256[] memory directAmounts = router.getAmountsOut(
            amountIn,
            directPath
        );

        // Indirect path: A -> B -> C
        address[] memory indirectPath = new address[](3);
        indirectPath[0] = address(tokenA);
        indirectPath[1] = address(tokenB);
        indirectPath[2] = address(tokenC);
        uint256[] memory indirectAmounts = router.getAmountsOut(
            amountIn,
            indirectPath
        );

        // Direct path should be more efficient (fewer fees)
        assertGt(
            directAmounts[1],
            indirectAmounts[2],
            "Direct path should yield more output"
        );
    }

    function test_MultiHop_FeesCompound() public {
        _createBalancedPools();

        uint256 amountIn = 10_000 * 10 ** 18;

        // Calculate fee loss at each hop
        address[] memory path2 = new address[](2);
        path2[0] = address(tokenA);
        path2[1] = address(tokenB);
        uint256[] memory amounts2 = router.getAmountsOut(amountIn, path2);

        address[] memory path3 = new address[](3);
        path3[0] = address(tokenA);
        path3[1] = address(tokenB);
        path3[2] = address(tokenC);
        uint256[] memory amounts3 = router.getAmountsOut(amountIn, path3);

        address[] memory path4 = new address[](4);
        path4[0] = address(tokenA);
        path4[1] = address(tokenB);
        path4[2] = address(tokenC);
        path4[3] = address(tokenD);
        uint256[] memory amounts4 = router.getAmountsOut(amountIn, path4);

        // Each additional hop should reduce output due to compounding fees
        // 2-hop output > 3-hop output > 4-hop output (relative to input)
        uint256 efficiency2 = (amounts2[1] * 10000) / amountIn;
        uint256 efficiency3 = (amounts3[2] * 10000) / amountIn;
        uint256 efficiency4 = (amounts4[3] * 10000) / amountIn;

        assertGt(
            efficiency2,
            efficiency3,
            "2-hop should be more efficient than 3-hop"
        );
        assertGt(
            efficiency3,
            efficiency4,
            "3-hop should be more efficient than 4-hop"
        );
    }

    // ============ INTERMEDIATE AMOUNTS TESTS ============

    function test_MultiHop_IntermediateAmountsCorrect() public {
        _createBalancedPools();

        address[] memory path = new address[](3);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        path[2] = address(tokenC);

        uint256 amountIn = 1000 * 10 ** 18;
        uint256[] memory amounts = router.getAmountsOut(amountIn, path);

        // Verify intermediate amount is correct
        // Get expected output of A->B
        address[] memory path1 = new address[](2);
        path1[0] = address(tokenA);
        path1[1] = address(tokenB);
        uint256[] memory amounts1 = router.getAmountsOut(amountIn, path1);

        assertEq(
            amounts[1],
            amounts1[1],
            "Intermediate amount should match direct A->B"
        );

        // Get expected output of B->C using intermediate amount
        address[] memory path2 = new address[](2);
        path2[0] = address(tokenB);
        path2[1] = address(tokenC);
        uint256[] memory amounts2 = router.getAmountsOut(amounts[1], path2);

        assertEq(amounts[2], amounts2[1], "Final amount should match B->C");
    }

    // ============ CIRCULAR PATH TESTS ============

    function test_MultiHop_CircularArbitrage() public {
        // Create pools with different ratios to enable arbitrage
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

        router.addLiquidity(
            address(tokenB),
            address(tokenC),
            100_000 * 10 ** 18,
            50_000 * 10 ** 18, // Imbalanced
            0,
            0,
            address(this),
            block.timestamp
        );

        router.addLiquidity(
            address(tokenC),
            address(tokenA),
            50_000 * 10 ** 18, // Imbalanced
            100_000 * 10 ** 18,
            0,
            0,
            address(this),
            block.timestamp
        );

        // Try circular swap: A -> B -> C -> A
        address[] memory path = new address[](4);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        path[2] = address(tokenC);
        path[3] = address(tokenA);

        uint256 amountIn = 1000 * 10 ** 18;
        uint256 balanceBefore = tokenA.balanceOf(address(this));

        router.swapExactTokensForTokens(
            amountIn,
            0,
            path,
            address(this),
            block.timestamp
        );

        uint256 balanceAfter = tokenA.balanceOf(address(this));

        // Calculate profit/loss safely
        int256 netChange = int256(balanceAfter) - int256(balanceBefore);

        // Due to fees, circular swap typically results in loss
        // Unless arbitrage opportunity exists
        emit log_named_int(
            "Net change from circular swap (negative = loss)",
            netChange
        );
    }

    // ============ REVERSE PATH TESTS ============

    function test_MultiHop_ReversePath() public {
        _createBalancedPools();

        uint256 amountIn = 1000 * 10 ** 18;

        // Forward: A -> B -> C
        address[] memory forwardPath = new address[](3);
        forwardPath[0] = address(tokenA);
        forwardPath[1] = address(tokenB);
        forwardPath[2] = address(tokenC);

        uint256 balanceABefore = tokenA.balanceOf(address(this));
        uint256 balanceCBefore = tokenC.balanceOf(address(this));

        router.swapExactTokensForTokens(
            amountIn,
            0,
            forwardPath,
            address(this),
            block.timestamp
        );

        uint256 cReceived = tokenC.balanceOf(address(this)) - balanceCBefore;

        // Reverse: C -> B -> A
        address[] memory reversePath = new address[](3);
        reversePath[0] = address(tokenC);
        reversePath[1] = address(tokenB);
        reversePath[2] = address(tokenA);

        router.swapExactTokensForTokens(
            cReceived,
            0,
            reversePath,
            address(this),
            block.timestamp
        );

        uint256 aReceived = tokenA.balanceOf(address(this)) -
            (balanceABefore - amountIn);

        // Should get less than original due to fees (round trip loss)
        assertLt(
            aReceived,
            amountIn,
            "Round trip should result in loss due to fees"
        );
    }

    // ============ SLIPPAGE IN MULTI-HOP ============

    function test_MultiHop_SlippageProtection() public {
        _createBalancedPools();

        address[] memory path = new address[](3);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        path[2] = address(tokenC);

        uint256 amountIn = 1000 * 10 ** 18;
        uint256[] memory amounts = router.getAmountsOut(amountIn, path);

        // Set impossible minimum
        uint256 impossibleMin = amounts[2] * 2;

        vm.expectRevert("Router: INSUFFICIENT_OUTPUT_AMOUNT");
        router.swapExactTokensForTokens(
            amountIn,
            impossibleMin,
            path,
            address(this),
            block.timestamp
        );
    }

    // ============ LARGE MULTI-HOP SWAP ============

    function test_MultiHop_LargeSwapPriceImpact() public {
        _createBalancedPools();

        // Small swap for baseline
        address[] memory path = new address[](3);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        path[2] = address(tokenC);

        uint256 smallAmount = 100 * 10 ** 18;
        uint256[] memory smallAmounts = router.getAmountsOut(smallAmount, path);
        uint256 smallEfficiency = (smallAmounts[2] * 10000) / smallAmount;

        // Large swap
        uint256 largeAmount = 10_000 * 10 ** 18;
        uint256[] memory largeAmounts = router.getAmountsOut(largeAmount, path);
        uint256 largeEfficiency = (largeAmounts[2] * 10000) / largeAmount;

        // Large swap should be less efficient due to price impact at each hop
        assertGt(
            smallEfficiency,
            largeEfficiency,
            "Large swap should have worse efficiency"
        );

        // Execute large swap
        router.swapExactTokensForTokens(
            largeAmount,
            0,
            path,
            address(this),
            block.timestamp
        );
    }

    // ============ GAS TEST FOR MULTI-HOP ============

    function test_MultiHop_GasUsage() public {
        _createBalancedPools();

        uint256 amountIn = 1000 * 10 ** 18;

        // 2-hop gas
        address[] memory path2 = new address[](2);
        path2[0] = address(tokenA);
        path2[1] = address(tokenB);

        uint256 gas2Start = gasleft();
        router.swapExactTokensForTokens(
            amountIn,
            0,
            path2,
            address(this),
            block.timestamp
        );
        uint256 gas2Used = gas2Start - gasleft();

        // 3-hop gas
        address[] memory path3 = new address[](3);
        path3[0] = address(tokenB);
        path3[1] = address(tokenC);
        path3[2] = address(tokenD);

        uint256 gas3Start = gasleft();
        router.swapExactTokensForTokens(
            amountIn / 2,
            0,
            path3,
            address(this),
            block.timestamp
        );
        uint256 gas3Used = gas3Start - gasleft();

        emit log_named_uint("Gas for 2-hop swap", gas2Used);
        emit log_named_uint("Gas for 3-hop swap", gas3Used);

        // 3-hop should use more gas
        assertGt(gas3Used, gas2Used, "More hops should use more gas");
    }
}
