// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/Factory.sol";
import "../src/Router.sol";
import "../src/Pair.sol";
import "../src/Oracle.sol";
import "../src/WETH9.sol";
import "../src/test/mocks/ERC20Mock.sol";

contract OracleTest is Test {
    Factory factory;
    Router router;
    Oracle oracle;
    WETH9 weth;
    ERC20Mock tokenA;
    ERC20Mock tokenB;
    Pair pair;

    function setUp() public {
        weth = new WETH9();
        factory = new Factory();
        router = new Router(address(factory), address(weth));
        oracle = new Oracle();

        tokenA = new ERC20Mock("Token A", "TKA", 18);
        tokenB = new ERC20Mock("Token B", "TKB", 18);

        tokenA.mint(address(this), 10_000_000 * 10 ** 18);
        tokenB.mint(address(this), 10_000_000 * 10 ** 18);
        tokenA.approve(address(router), type(uint256).max);
        tokenB.approve(address(router), type(uint256).max);

        // Create initial pool 1:1
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            1000 * 10 ** 18,
            1000 * 10 ** 18,
            0,
            0,
            address(this),
            block.timestamp
        );

        pair = Pair(factory.getPair(address(tokenA), address(tokenB)));
    }

    function test_Accumulation() public {
        // Initial state
        (uint112 r0, uint112 r1, ) = pair.getReserves();
        assertEq(r0, 1000 * 10 ** 18);
        assertEq(r1, 1000 * 10 ** 18);

        // Advance time 100 seconds
        vm.warp(block.timestamp + 100);
        
        // Force Pair update to store cumulative prices
        pair.sync();

        // Check cumulative prices in Pair
        assertTrue(pair.price0CumulativeLast() > 0, "Price0 Cumulative should increase");
        assertTrue(pair.price1CumulativeLast() > 0, "Price1 Cumulative should increase");
    }

    function test_Consult() public {
        uint256 start = block.timestamp;
        
        // Advance time to calculate valid TWAP window
        vm.warp(start + 1000);
        oracle.update(address(pair));
        
        // Advance another period
        uint period = 1000;
        vm.warp(start + 2000);
        oracle.update(address(pair));

        // Consult price
        uint256 price = oracle.consult(address(pair), period);
        
        // 1e18 in Q112 is 2**112
        uint256 expectedPrice = uint256(1) << 112; 
        
        // Allow tiny error due to time resolution
        uint256 error = expectedPrice / 1000; 
        assertApproxEqAbs(price, expectedPrice, error, "TWAP should be approx 1.0");
    }

    function test_ManipulationResistance() public {
        uint256 start = block.timestamp;
        
        // Establish baseline
        vm.warp(start + 3600); // 1 hour history
        oracle.update(address(pair));

        // Advance 1 hour
        vm.warp(start + 7200);
        oracle.update(address(pair)); // Record stable price

        // Manipulate price heavily (Flash loan style)
        // Swap huge amount of A for B
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        
        // Ensure timestamp doesn't change during swap (instant)
        
        router.swapExactTokensForTokens(
            500 * 10 ** 18, // 50of pool
            0,
            path,
            address(this),
            block.timestamp
        );

        // Verify TWAP remained stable despite spot price crash
        uint256 period = 3600; 
        uint256 twapPrice = oracle.consult(address(pair), period);
        uint256 spotPrice = oracle.getSpotPrice(address(pair));
        
        // Q112 to 18 decimals for comparison
        uint256 twap18 = (twapPrice * 1e18) >> 112;
        
        // TWAP should remain stable (approx 1.0)
        assertApproxEqAbs(twap18, 1e18, 0.1e18, "TWAP should resist manipulation");
        
        // Spot price should be SIGNIFICANTLY different from 1.0 (moved by ~50% trade)
        // Price impact of 50% trade is huge.
        bool spotIsStable = spotPrice > 0.9e18 && spotPrice < 1.1e18;
        assertFalse(spotIsStable, "Spot price should reflect manipulation");
    }
}
