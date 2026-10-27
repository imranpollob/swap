// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/Factory.sol";
import "../src/Router.sol";
import "../src/Pair.sol";
import "../src/WETH9.sol";
import "../src/test/mocks/ERC20Mock.sol";

/// @notice Independent constant-product reference, written from the math
/// (not from the Router code): x*y=k with a 0.3% fee.
/// amountOut = amountIn*997*reserveOut / (reserveIn*1000 + amountIn*997).
library AmmMathRef {
    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut)
        internal
        pure
        returns (uint256)
    {
        uint256 feeAdjustedIn = amountIn * 997;
        return (feeAdjustedIn * reserveOut) / (reserveIn * 1000 + feeAdjustedIn);
    }

    function getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut)
        internal
        pure
        returns (uint256)
    {
        return ((reserveIn * amountOut * 1000) / ((reserveOut - amountOut) * 997)) + 1;
    }
}

contract SwapFuzzTest is Test {
    Factory factory;
    Router router;
    WETH9 weth;
    ERC20Mock tokenA;
    ERC20Mock tokenB;

    function setUp() public {
        weth = new WETH9();
        factory = new Factory();
        router = new Router(address(factory), address(weth));

        tokenA = new ERC20Mock("Token A", "TKA", 18);
        tokenB = new ERC20Mock("Token B", "TKB", 18);

        tokenA.mint(address(this), type(uint128).max);
        tokenB.mint(address(this), type(uint128).max);

        tokenA.approve(address(router), type(uint256).max);
        tokenB.approve(address(router), type(uint256).max);
    }

    function _orderedReserves() internal view returns (uint256 rIn, uint256 rOut) {
        Pair pool = Pair(factory.getPair(address(tokenA), address(tokenB)));
        (uint112 r0, uint112 r1,) = pool.getReserves();
        (rIn, rOut) = address(tokenA) < address(tokenB)
            ? (uint256(r0), uint256(r1))
            : (uint256(r1), uint256(r0));
    }

    /// Router execution matches first-principles math on real pool state.
    /// NOTE: inputs are folded into range with % (not bound), because
    /// forge's bound() wraps below-min values to the TOP of the range.
    function testFuzz_RouterMatchesIndependentMath(uint128 liqSeed, uint128 amountIn) public {
        uint256 liqA = 1e12 + (uint256(liqSeed) % (1_000_000 * 10 ** 18 - 1e12));
        uint256 liqB = 1e12 + ((uint256(liqSeed) * 7919 + 1) % (1_000_000 * 10 ** 18 - 1e12));
        uint256 amtIn = 1000 + (uint256(amountIn) % (1_000_000 * 10 ** 18 - 1000));

        router.addLiquidity(
            address(tokenA), address(tokenB), liqA, liqB, 0, 0, address(this), block.timestamp
        );

        (uint256 rIn, uint256 rOut) = _orderedReserves();
        uint256 expected = AmmMathRef.getAmountOut(amtIn, rIn, rOut);
        // Dust into an imbalanced pool quotes zero; zero-output swaps revert
        // by design (Pair: INSUFFICIENT_OUTPUT_AMOUNT), so skip.
        if (expected == 0) return;

        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        // Router's own quote must also match the reference.
        uint256[] memory quoted = router.getAmountsOut(amtIn, path);
        assertEq(quoted[1], expected, "router quote matches reference math");

        uint256 balanceBefore = tokenB.balanceOf(address(this));
        router.swapExactTokensForTokens(amtIn, 0, path, address(this), block.timestamp);
        assertEq(
            tokenB.balanceOf(address(this)) - balanceBefore,
            expected,
            "executed swap matches reference math"
        );
    }

    /// Round-trip swaps always lose to fees (fee property, not code path).
    function testFuzz_RoundTripLosesToFees(uint128 amountIn) public {
        uint256 amtIn = 1e12 + (uint256(amountIn) % (50_000 * 10 ** 18 - 1e12));

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

        uint256 balanceBefore = tokenA.balanceOf(address(this));

        // Swap back ONLY what the forward leg returned: swapping the whole
        // (huge setUp-minted) balance would dwarf the pool and must revert.
        address[] memory fwd = new address[](2);
        fwd[0] = address(tokenA);
        fwd[1] = address(tokenB);
        uint256 midBefore = tokenB.balanceOf(address(this));
        router.swapExactTokensForTokens(amtIn, 0, fwd, address(this), block.timestamp);
        uint256 received = tokenB.balanceOf(address(this)) - midBefore;
        if (received == 0) return; // dust leg: nothing to round-trip

        address[] memory back = new address[](2);
        back[0] = address(tokenB);
        back[1] = address(tokenA);
        router.swapExactTokensForTokens(received, 0, back, address(this), block.timestamp);

        assertLt(tokenA.balanceOf(address(this)), balanceBefore, "round trip must lose to fees");
    }

    /// getAmountsIn is consistent with execution: funding the quoted input
    /// yields at least the requested output.
    function testFuzz_AmountInQuoteIsSufficient(uint128 amountOut) public {
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

        vm.assume(amountOut > 1000);
        vm.assume(amountOut < 50_000 * 10 ** 18);

        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        uint256[] memory quoted = router.getAmountsIn(amountOut, path);

        // Independent check on the quoted input leg.
        (uint256 rIn, uint256 rOut) = _orderedReserves();
        assertEq(
            quoted[0],
            AmmMathRef.getAmountIn(amountOut, rIn, rOut),
            "getAmountsIn matches reference math"
        );

        uint256 balanceBefore = tokenB.balanceOf(address(this));
        router.swapExactTokensForTokens(quoted[0], amountOut, path, address(this), block.timestamp);
        assertGe(
            tokenB.balanceOf(address(this)) - balanceBefore,
            amountOut,
            "quoted input must produce requested output"
        );
    }
}
