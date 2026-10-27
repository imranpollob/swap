// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/StdInvariant.sol";
import "solmate/utils/FixedPointMathLib.sol";
import "../src/Factory.sol";
import "../src/Router.sol";
import "../src/Pair.sol";
import "../src/Oracle.sol";
import "../src/WETH9.sol";
import "../src/test/mocks/ERC20Mock.sol";

/// @notice Stateful handler with ghost accounting. All LP goes to the handler
/// itself so token conservation is checkable; invalid inputs are skipped
/// explicitly (never swallowed) since fail_on_revert is on.
contract Handler is Test {
    Factory factory;
    Router router;
    Pair pair;
    Oracle oracle;
    ERC20Mock tokenA;
    ERC20Mock tokenB;

    // Ghosts.
    uint256 public mintedA;
    uint256 public mintedB;
    uint256 public snapC0;
    uint256 public snapC1;
    uint256 public kBeforeSwap;
    uint256 public kAfterSwap;

    constructor(
        Factory _factory,
        Router _router,
        Pair _pair,
        Oracle _oracle,
        ERC20Mock _tokenA,
        ERC20Mock _tokenB
    ) {
        factory = _factory;
        router = _router;
        pair = _pair;
        oracle = _oracle;
        tokenA = _tokenA;
        tokenB = _tokenB;

        tokenA.approve(address(router), type(uint256).max);
        tokenB.approve(address(router), type(uint256).max);
    }

    function _snapCumulative() internal {
        snapC0 = pair.price0CumulativeLast();
        snapC1 = pair.price1CumulativeLast();
    }

    function _tokenReserves() internal view returns (uint256 rA, uint256 rB) {
        (uint112 r0, uint112 r1,) = pair.getReserves();
        (rA, rB) = address(tokenA) < address(tokenB)
            ? (uint256(r0), uint256(r1))
            : (uint256(r1), uint256(r0));
    }

    function addLiquidity(uint amountA, uint amountB) public {
        amountA = bound(amountA, 1, 1_000_000 * 1e18);
        amountB = bound(amountB, 1, 1_000_000 * 1e18);
        _snapCumulative();

        // Skip deposits that would mint zero LP (dust relative to reserves).
        (uint256 rA, uint256 rB) = _tokenReserves();
        uint256 supply = pair.totalSupply();
        if (supply == 0) {
            if (amountA <= (1001 * 1001 - 1) / amountB) return;
        } else {
            if (rA == 0 || rB == 0) return;
            uint256 amountBOptimal = (amountA * rB) / rA;
            (uint256 depA, uint256 depB) = amountBOptimal <= amountB
                ? (amountA, amountBOptimal)
                : ((amountB * rA) / rB, amountB);
            uint256 liq =
                depA * supply / rA < depB * supply / rB ? depA * supply / rA : depB * supply / rB;
            if (liq == 0) return;
        }

        tokenA.mint(address(this), amountA);
        tokenB.mint(address(this), amountB);
        mintedA += amountA;
        mintedB += amountB;

        router.addLiquidity(
            address(tokenA), address(tokenB), amountA, amountB, 0, 0, address(this), block.timestamp
        );
    }

    function removeLiquidity(uint liquidity) public {
        _snapCumulative();
        uint256 bal = pair.balanceOf(address(this));
        if (bal == 0) return;
        liquidity = bound(liquidity, 1, bal);

        // Skip if the pro-rata burn would round to zero on either side.
        uint256 supply = pair.totalSupply();
        (uint256 bA, uint256 bB) = address(tokenA) < address(tokenB)
            ? (tokenA.balanceOf(address(pair)), tokenB.balanceOf(address(pair)))
            : (tokenB.balanceOf(address(pair)), tokenA.balanceOf(address(pair)));
        if ((liquidity * bA) / supply == 0) return;
        if ((liquidity * bB) / supply == 0) return;

        pair.approve(address(router), type(uint256).max);
        router.removeLiquidity(
            address(tokenA), address(tokenB), liquidity, 0, 0, address(this), block.timestamp
        );
    }

    function swap(uint amountIn, bool zeroForOne) public {
        amountIn = bound(amountIn, 1, 100 * 1e18);
        _snapCumulative();

        // Skip when the pool cannot serve the swap: with fail_on_revert the
        // handler must not submit invalid inputs. Quote first (revert-free
        // once reserves are nonzero) and skip dust that would output zero.
        (uint256 rAq, uint256 rBq) = _tokenReserves();
        (uint256 rIn, uint256 rOut) = zeroForOne ? (rAq, rBq) : (rBq, rAq);
        if (rIn == 0 || rOut == 0) return;

        address[] memory path = new address[](2);
        if (zeroForOne) {
            path[0] = address(tokenA);
            path[1] = address(tokenB);
        } else {
            path[0] = address(tokenB);
            path[1] = address(tokenA);
        }
        uint256[] memory quoted = router.getAmountsOut(amountIn, path);
        if (quoted[quoted.length - 1] == 0) return;

        if (zeroForOne) {
            tokenA.mint(address(this), amountIn);
            mintedA += amountIn;
        } else {
            tokenB.mint(address(this), amountIn);
            mintedB += amountIn;
        }

        (uint256 rA2, uint256 rB2) = _tokenReserves();
        (uint256 rIn2, uint256 rOut2) = zeroForOne ? (rA2, rB2) : (rB2, rA2);
        kBeforeSwap = rIn2 * rOut2;

        router.swapExactTokensForTokens(amountIn, 0, path, address(this), block.timestamp);

        (rA2, rB2) = _tokenReserves();
        (rIn2, rOut2) = zeroForOne ? (rA2, rB2) : (rB2, rA2);
        kAfterSwap = rIn2 * rOut2;
    }

    function elapse(uint dt) public {
        dt = bound(dt, 1, 3600);
        _snapCumulative();
        vm.warp(block.timestamp + dt);
    }

    function oracleUpdate() public {
        _snapCumulative();
        oracle.update(address(pair));
    }
}

contract InvariantTest is StdInvariant, Test {
    Factory factory;
    Router router;
    Oracle oracle;
    WETH9 weth;
    ERC20Mock tokenA;
    ERC20Mock tokenB;
    Pair pair;
    Handler handler;

    function _tokenBalances() internal view returns (uint256 bA, uint256 bB) {
        // NOTE: intentionally NOT sorted — bA is always tokenA's balance.
        // Callers map to (reserve0, reserve1) by comparing token addresses.
        bA = tokenA.balanceOf(address(pair));
        bB = tokenB.balanceOf(address(pair));
    }

    function setUp() public {
        weth = new WETH9();
        factory = new Factory();
        router = new Router(address(factory), address(weth));
        oracle = new Oracle(address(factory));

        tokenA = new ERC20Mock("Token A", "TKA", 18);
        tokenB = new ERC20Mock("Token B", "TKB", 18);

        address pairAddress = factory.createPair(address(tokenA), address(tokenB));
        pair = Pair(pairAddress);

        handler = new Handler(factory, router, pair, oracle, tokenA, tokenB);
        targetContract(address(handler));
    }

    function invariant_reservesMatchBalances() public view {
        (uint112 r0, uint112 r1,) = pair.getReserves();
        (uint256 bA, uint256 bB) = _tokenBalances();
        if (address(tokenA) < address(tokenB)) {
            assertEq(r0, bA, "reserve0 == tokenA balance");
            assertEq(r1, bB, "reserve1 == tokenB balance");
        } else {
            assertEq(r0, bB, "reserve0 == tokenB balance");
            assertEq(r1, bA, "reserve1 == tokenA balance");
        }
    }

    function invariant_lpSupplyBacked() public view {
        (uint112 r0, uint112 r1,) = pair.getReserves();
        uint256 supply = pair.totalSupply();
        // Fees grow k without minting, so supply never exceeds sqrt(k).
        uint256 root = FixedPointMathLib.sqrt(uint256(r0) * r1);
        assertLe(supply, root + 1, "LP supply backed by sqrt(k)");
    }

    function invariant_kNonDecreasingOnSwap() public view {
        assertGe(handler.kAfterSwap(), handler.kBeforeSwap(), "k never decreases on swap (fees)");
    }

    function invariant_tokenConservation() public view {
        // Handler is the only minter and all funds stay in
        // {handler, pair, router}; router is empty after each call.
        assertEq(
            tokenA.totalSupply(),
            tokenA.balanceOf(address(pair)) + tokenA.balanceOf(address(router))
                + tokenA.balanceOf(address(handler)),
            "tokenA conserved"
        );
        assertEq(
            tokenB.totalSupply(),
            tokenB.balanceOf(address(pair)) + tokenB.balanceOf(address(router))
                + tokenB.balanceOf(address(handler)),
            "tokenB conserved"
        );
        assertEq(tokenA.totalSupply(), handler.mintedA(), "mints tracked A");
        assertEq(tokenB.totalSupply(), handler.mintedB(), "mints tracked B");
    }

    function invariant_routerHoldsNoFunds() public view {
        assertEq(tokenA.balanceOf(address(router)), 0, "router holds no A");
        assertEq(tokenB.balanceOf(address(router)), 0, "router holds no B");
        assertEq(address(router).balance, 0, "router holds no ETH");
    }

    function invariant_oracleBounded() public view {
        assertLe(
            oracle.observationCount(address(pair)), oracle.MAX_OBSERVATIONS(), "observations capped"
        );
        if (oracle.observationCount(address(pair)) > 0) {
            assertLe(
                oracle.latestObservation(address(pair)).timestamp,
                block.timestamp,
                "observations never from the future"
            );
        }
    }

    function invariant_cumulativeMonotonic() public view {
        assertGe(
            pair.price0CumulativeLast(),
            handler.snapC0(),
            "cumulative0 monotonic since action start"
        );
        assertGe(
            pair.price1CumulativeLast(),
            handler.snapC1(),
            "cumulative1 monotonic since action start"
        );
    }

    function invariant_factoryConsistency() public view {
        assertEq(
            factory.getPair(address(tokenA), address(tokenB)),
            factory.getPair(address(tokenB), address(tokenA)),
            "pair symmetry"
        );
        assertEq(
            factory.getPair(address(tokenA), address(tokenB)), address(pair), "pair registered"
        );
        assertEq(pair.factory(), address(factory), "pair points at factory");
        assertEq(
            factory.computePairAddress(address(tokenA), address(tokenB)),
            address(pair),
            "CREATE2 prediction matches"
        );
        assertEq(factory.allPairsLength(), 1, "no rogue pairs");
    }
}
