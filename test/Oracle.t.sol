// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/Factory.sol";
import "../src/Router.sol";
import "../src/Pair.sol";
import "../src/Oracle.sol";
import "../src/WETH9.sol";
import "../src/test/mocks/ERC20Mock.sol";

/// @notice Unit tests for the ring-buffer TWAP oracle.
/// Attack coverage lives in test/exploits/.
contract OracleTest is Test {
    uint256 constant T0 = 1_000_000;

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
        oracle = new Oracle(address(factory));

        tokenA = new ERC20Mock("Token A", "TKA", 18);
        tokenB = new ERC20Mock("Token B", "TKB", 18);

        tokenA.mint(address(this), 10_000_000 * 10 ** 18);
        tokenB.mint(address(this), 10_000_000 * 10 ** 18);
        tokenA.approve(address(router), type(uint256).max);
        tokenB.approve(address(router), type(uint256).max);

        vm.warp(T0);
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
        vm.warp(T0 + 600);
        pair.sync();
        assertGt(pair.price0CumulativeLast(), 0, "Price0 Cumulative should increase");
        assertGt(pair.price1CumulativeLast(), 0, "Price1 Cumulative should increase");

        oracle.update(address(pair));
        vm.warp(T0 + 1200);
        pair.sync();
        oracle.update(address(pair));

        assertEq(oracle.observationCount(address(pair)), 2);
        Oracle.Observation memory latest = oracle.latestObservation(address(pair));
        assertEq(latest.timestamp, T0 + 1200);
    }

    function test_Consult() public {
        vm.warp(T0 + 3600);
        oracle.update(address(pair));

        vm.warp(T0 + 7200);
        pair.sync();
        oracle.update(address(pair));

        uint256 price = oracle.consult(address(pair), 3600);

        uint256 expectedPrice = uint256(1) << 112;
        uint256 error = expectedPrice / 1000;
        assertApproxEqAbs(price, expectedPrice, error, "TWAP approx 1.0");
    }

    function test_ManipulationResistance() public {
        // Establish baseline
        vm.warp(T0 + 3600);
        oracle.update(address(pair));

        // Advance 1 hour
        vm.warp(T0 + 7200);
        oracle.update(address(pair)); // Record stable price

        // Manipulate price heavily (flash-loan style)
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        router.swapExactTokensForTokens(
            500 * 10 ** 18, // 50% of pool
            0,
            path,
            address(this),
            block.timestamp
        );

        // Verify TWAP remained stable despite spot price crash
        uint256 period = 3600;
        uint256 twapPrice = oracle.consult(address(pair), period);
        uint256 spotPrice = oracle.getSpotPriceUnsafe(address(pair));

        // Q112 to 18 decimals for comparison
        uint256 twap18 = (twapPrice * 1e18) >> 112;

        // TWAP should remain stable (approx 1.0)
        assertApproxEqAbs(twap18, 1e18, 0.1e18, "TWAP resists manipulation");

        // Spot price should be SIGNIFICANTLY different from 1.0
        bool spotIsStable = spotPrice > 0.9e18 && spotPrice < 1.1e18;
        assertFalse(spotIsStable, "Spot price reflects manipulation");
    }

    function test_Revert_PeriodTooShort() public {
        vm.expectRevert("Oracle: PERIOD_TOO_SHORT");
        oracle.consult(address(pair), 60);
    }

    function test_Revert_PeriodTooLong() public {
        uint256 maxPeriod = oracle.MAX_TWAP_PERIOD();
        vm.expectRevert("Oracle: PERIOD_TOO_LONG");
        oracle.consult(address(pair), maxPeriod + 1);
    }

    function test_Revert_InsufficientObservations() public {
        // Zero observations.
        vm.expectRevert("Oracle: INSUFFICIENT_OBSERVATIONS");
        oracle.consult(address(pair), 3600);

        // One observation is still not enough.
        vm.warp(T0 + 3600);
        oracle.update(address(pair));
        vm.expectRevert("Oracle: INSUFFICIENT_OBSERVATIONS");
        oracle.consult(address(pair), 3600);
    }

    function test_FreshnessBoundary() public {
        vm.warp(T0);
        oracle.update(address(pair));
        vm.warp(T0 + 900);
        pair.sync();
        oracle.update(address(pair));

        uint256 maxAge = oracle.MAX_OBSERVATION_AGE();
        // Exactly MAX_AGE old: still accepted (revert only when strictly greater).
        vm.warp(T0 + 900 + maxAge);
        oracle.consult(address(pair), 900);

        // One second later: stale.
        vm.warp(T0 + 900 + maxAge + 1);
        vm.expectRevert("Oracle: STALE_OBSERVATION");
        oracle.consult(address(pair), 900);
    }

    function test_IsReady() public {
        assertFalse(oracle.isReady(address(pair), 3600));

        vm.warp(T0);
        oracle.update(address(pair));
        assertFalse(oracle.isReady(address(pair), 3600));

        vm.warp(T0 + 3600);
        pair.sync();
        oracle.update(address(pair));
        assertTrue(oracle.isReady(address(pair), 3600));
        // Full window missing for longer periods.
        assertFalse(oracle.isReady(address(pair), 1 days));
    }

    function test_GetObservationIndexing() public {
        vm.warp(T0 + 600);
        oracle.update(address(pair));
        vm.warp(T0 + 1200);
        oracle.update(address(pair));
        vm.warp(T0 + 1800);
        oracle.update(address(pair));

        assertEq(oracle.getObservation(address(pair), 0).timestamp, T0 + 600);
        assertEq(oracle.getObservation(address(pair), 1).timestamp, T0 + 1200);
        assertEq(oracle.getObservation(address(pair), 2).timestamp, T0 + 1800);
        assertEq(oracle.latestObservation(address(pair)).timestamp, T0 + 1800);

        vm.expectRevert("Oracle: INDEX_OUT_OF_RANGE");
        oracle.getObservation(address(pair), 3);
    }

    function test_RateLimitedUpdate() public {
        vm.warp(T0 + 3600);
        oracle.update(address(pair));
        assertEq(oracle.observationCount(address(pair)), 1);

        // Same block / within the interval: skipped, not duplicated.
        oracle.update(address(pair));
        vm.warp(T0 + 3600 + 60);
        oracle.update(address(pair));
        assertEq(oracle.observationCount(address(pair)), 1);

        // Past the interval: recorded.
        vm.warp(T0 + 3600 + 300);
        oracle.update(address(pair));
        assertEq(oracle.observationCount(address(pair)), 2);
    }

    function test_UpdateMany() public {
        ERC20Mock tokenC = new ERC20Mock("Token C", "TKC", 18);
        ERC20Mock tokenD = new ERC20Mock("Token D", "TKD", 18);
        tokenC.mint(address(this), 10_000 * 1e18);
        tokenD.mint(address(this), 10_000 * 1e18);
        tokenC.approve(address(router), type(uint256).max);
        tokenD.approve(address(router), type(uint256).max);
        vm.warp(T0);
        router.addLiquidity(
            address(tokenC),
            address(tokenD),
            1000 * 1e18,
            1000 * 1e18,
            0,
            0,
            address(this),
            block.timestamp
        );
        Pair pair2 = Pair(factory.getPair(address(tokenC), address(tokenD)));

        address[] memory pairs = new address[](2);
        pairs[0] = address(pair);
        pairs[1] = address(pair2);
        oracle.updateMany(pairs);
        assertEq(oracle.observationCount(address(pair)), 1);
        assertEq(oracle.observationCount(address(pair2)), 1);
    }

    function test_ConsultScaled() public {
        vm.warp(T0 + 3600);
        oracle.update(address(pair));
        vm.warp(T0 + 7200);
        pair.sync();
        oracle.update(address(pair));

        uint256 scaled = oracle.consultScaled(address(pair), 3600);
        assertApproxEqAbs(scaled, 1e18, 1e15, "scaled TWAP approx 1.0");
    }

    function test_ConsultScaledDecimals() public {
        ERC20Mock usdc = new ERC20Mock("USD Coin", "USDC", 6);
        usdc.mint(address(this), 1_000_000 * 1e6);
        usdc.approve(address(router), type(uint256).max);
        // addLiquidity pulls real WETH (not ETH): fund and approve it.
        vm.deal(address(this), 2000 * 1e18);
        weth.deposit{ value: 1000 * 1e18 }();
        weth.approve(address(router), type(uint256).max);
        vm.warp(T0);
        router.addLiquidity(
            address(usdc),
            address(weth),
            1000 * 1e6,
            1000 * 1e18,
            0,
            0,
            address(this),
            block.timestamp
        );
        Pair usdcPair = Pair(factory.getPair(address(usdc), address(weth)));

        vm.warp(T0 + 1800);
        oracle.update(address(usdcPair));
        vm.warp(T0 + 3600);
        oracle.update(address(usdcPair));

        // 1 whole USDC ~= 1 WETH in this 1:1 pool.
        uint256 price =
            oracle.consultScaledDecimals(address(usdcPair), address(usdc), address(weth), 1800);
        assertApproxEqRel(price, 1e18, 0.01e18, "USDC/WETH approx 1.0");
    }

    function test_ManipulationGuardTracksTwap() public {
        // Healthy market tracking its TWAP: guard passes.
        vm.warp(T0 + 3600);
        oracle.update(address(pair));
        vm.warp(T0 + 7200);
        oracle.update(address(pair));
        assertFalse(oracle.isPriceManipulated(address(pair), 3600, 1000));

        // Spot moves far from TWAP: guard trips.
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        router.swapExactTokensForTokens(500 * 10 ** 18, 0, path, address(this), block.timestamp);
        assertTrue(oracle.isPriceManipulated(address(pair), 3600, 1000));
    }
}
