// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/Factory.sol";
import "../src/Router.sol";
import "../src/Pair.sol";
import "../src/WETH9.sol";
import "../src/test/mocks/ERC20Mock.sol";

contract SwapTest is Test {
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

        tokenA.mint(address(this), 1000 * 10 ** 18);
        tokenB.mint(address(this), 1000 * 10 ** 18);

        tokenA.approve(address(router), type(uint).max);
        tokenB.approve(address(router), type(uint).max);
    }

    function testAddLiquidity() public {
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

        address pairAddress = factory.getPair(address(tokenA), address(tokenB));
        Pair pair = Pair(pairAddress);

        (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();
        assertEq(reserve0, 100 * 10 ** 18);
        assertEq(reserve1, 100 * 10 ** 18);
        assertGt(pair.totalSupply(), 0);
    }

    function testSwap() public {
        // Add liquidity first
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

        uint amountIn = 10 * 10 ** 18;
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        uint[] memory amounts = router.getAmountsOut(amountIn, path);
        uint amountOutMin = (amounts[1] * 99) / 100; // 1% slippage

        uint balanceBefore = tokenB.balanceOf(address(this));

        router.swapExactTokensForTokens(
            amountIn,
            amountOutMin,
            path,
            address(this),
            block.timestamp
        );

        uint balanceAfter = tokenB.balanceOf(address(this));
        assertEq(balanceAfter - balanceBefore, amounts[1]);
    }

    function testFailSwapExpired() public {
        // Add liquidity first
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

        router.swapExactTokensForTokens(
            1 * 10 ** 18,
            0,
            path,
            address(this),
            block.timestamp - 1 // Expired
        );
    }
}
