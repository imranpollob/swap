// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/Factory.sol";
import "../src/Router.sol";
import "../src/Pair.sol";
import "../src/WETH9.sol";
import "../src/test/mocks/ERC20Mock.sol";

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

    function testFuzz_SwapCorrectness(uint128 amountIn) public {
        vm.assume(amountIn > 1000); // Minimum amount
        vm.assume(amountIn < 1_000_000 * 10 ** 18); // Reasonable cap

        // Add liquidity
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

        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        uint[] memory expectedAmounts = router.getAmountsOut(amountIn, path);

        uint balanceBefore = tokenB.balanceOf(address(this));
        router.swapExactTokensForTokens(
            amountIn,
            0,
            path,
            address(this),
            block.timestamp
        );
        uint balanceAfter = tokenB.balanceOf(address(this));

        assertEq(
            balanceAfter - balanceBefore,
            expectedAmounts[1],
            "Swap output mismatch"
        );
    }
}
