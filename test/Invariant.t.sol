// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/StdInvariant.sol";
import "../src/Factory.sol";
import "../src/Router.sol";
import "../src/Pair.sol";
import "../src/WETH9.sol";
import "../src/test/mocks/ERC20Mock.sol";

contract Handler is Test {
    Factory factory;
    Router router;
    Pair pair;
    ERC20Mock tokenA;
    ERC20Mock tokenB;

    constructor(
        Factory _factory,
        Router _router,
        Pair _pair,
        ERC20Mock _tokenA,
        ERC20Mock _tokenB
    ) {
        factory = _factory;
        router = _router;
        pair = _pair;
        tokenA = _tokenA;
        tokenB = _tokenB;

        tokenA.approve(address(router), type(uint256).max);
        tokenB.approve(address(router), type(uint256).max);
    }

    function addLiquidity(uint amountA, uint amountB) public {
        amountA = bound(amountA, 1, 1_000_000 * 1e18);
        amountB = bound(amountB, 1, 1_000_000 * 1e18);

        tokenA.mint(address(this), amountA);
        tokenB.mint(address(this), amountB);

        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            amountA,
            amountB,
            0,
            0,
            msg.sender, // ghost user
            block.timestamp
        );
    }

    function swap(uint amountIn, bool zeroForOne) public {
        amountIn = bound(amountIn, 1, 100 * 1e18);

        address[] memory path = new address[](2);
        if (zeroForOne) {
            tokenA.mint(address(this), amountIn);
            path[0] = address(tokenA);
            path[1] = address(tokenB);
        } else {
            tokenB.mint(address(this), amountIn);
            path[0] = address(tokenB);
            path[1] = address(tokenA);
        }

        try
            router.swapExactTokensForTokens(
                amountIn,
                0,
                path,
                msg.sender,
                block.timestamp
            )
        {} catch {}
    }
}

contract InvariantTest is StdInvariant, Test {
    Factory factory;
    Router router;
    WETH9 weth;
    ERC20Mock tokenA;
    ERC20Mock tokenB;
    Pair pair;
    Handler handler;

    function setUp() public {
        weth = new WETH9();
        factory = new Factory();
        router = new Router(address(factory), address(weth));

        tokenA = new ERC20Mock("Token A", "TKA", 18);
        tokenB = new ERC20Mock("Token B", "TKB", 18);

        address pairAddress = factory.createPair(
            address(tokenA),
            address(tokenB)
        );
        pair = Pair(pairAddress);

        handler = new Handler(factory, router, pair, tokenA, tokenB);
        targetContract(address(handler));
    }

    function invariant_reservesMatchBalances() public view {
        (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();
        uint balance0 = tokenA.balanceOf(address(pair)); // Use variable to decide 0/1 sorting logic?
        // Note: tokenA might be token0 or token1.

        (address t0, ) = sortTokens(address(tokenA), address(tokenB));
        if (t0 == address(tokenA)) {
            assertLe(reserve0, tokenA.balanceOf(address(pair)));
            assertLe(reserve1, tokenB.balanceOf(address(pair)));
        } else {
            assertLe(reserve0, tokenB.balanceOf(address(pair)));
            assertLe(reserve1, tokenA.balanceOf(address(pair)));
        }
    }

    function sortTokens(
        address tokenA,
        address tokenB
    ) internal pure returns (address token0, address token1) {
        (token0, token1) = tokenA < tokenB
            ? (tokenA, tokenB)
            : (tokenB, tokenA);
    }
}
