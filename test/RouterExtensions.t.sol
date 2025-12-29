// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/Factory.sol";
import "../src/Router.sol";
import "../src/Pair.sol";
import "../src/WETH9.sol";
import "../src/test/mocks/ERC20Mock.sol";

/**
 * @title Router Extensions Test Suite
 * @notice Tests for swapTokensForExactTokens, ETH wrapper functions, and getAmountsIn
 */
contract RouterExtensionsTest is Test {
    Factory factory;
    Router router;
    WETH9 weth;
    ERC20Mock tokenA;
    Pair pair;

    address user = address(0x1234);

    receive() external payable {}

    function setUp() public {
        weth = new WETH9();
        factory = new Factory();
        router = new Router(address(factory), address(weth));

        tokenA = new ERC20Mock("Token A", "TKA", 18);

        // Fund user
        tokenA.mint(user, 1_000_000 * 10 ** 18);
        vm.deal(user, 1000 ether);

        // Fund test contract
        tokenA.mint(address(this), 1_000_000 * 10 ** 18);
        vm.deal(address(this), 1000 ether);
        tokenA.approve(address(router), type(uint256).max);

        // Create and fund pool with initial liquidity
        weth.deposit{value: 100 ether}();
        weth.approve(address(router), type(uint256).max);

        router.addLiquidity(
            address(tokenA),
            address(weth),
            10_000 * 10 ** 18,
            100 ether,
            0,
            0,
            address(this),
            block.timestamp
        );

        address pairAddress = factory.getPair(address(tokenA), address(weth));
        pair = Pair(pairAddress);
    }

    // ============ getAmountsIn TESTS ============

    function test_GetAmountsIn_Basic() public view {
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(weth);

        uint256 amountOut = 1 ether;
        uint256[] memory amounts = router.getAmountsIn(amountOut, path);

        assertEq(amounts.length, 2, "Should have 2 amounts");
        assertEq(amounts[1], amountOut, "Output should match requested");
        assertGt(amounts[0], 0, "Input should be positive");
    }

    function test_GetAmountsIn_MultiHop() public {
        // Create tokenB and second pool
        ERC20Mock tokenB = new ERC20Mock("Token B", "TKB", 18);
        tokenB.mint(address(this), 1_000_000 * 10 ** 18);
        tokenB.approve(address(router), type(uint256).max);

        // Need more WETH for second pool
        weth.deposit{value: 100 ether}();

        router.addLiquidity(
            address(tokenB),
            address(weth),
            10_000 * 10 ** 18,
            100 ether,
            0,
            0,
            address(this),
            block.timestamp
        );

        address[] memory path = new address[](3);
        path[0] = address(tokenA);
        path[1] = address(weth);
        path[2] = address(tokenB);

        uint256 amountOut = 100 * 10 ** 18;
        uint256[] memory amounts = router.getAmountsIn(amountOut, path);

        assertEq(amounts.length, 3, "Should have 3 amounts");
        assertEq(amounts[2], amountOut, "Final output should match");
        assertGt(amounts[1], 0, "Intermediate should be positive");
        assertGt(amounts[0], 0, "Input should be positive");
    }

    // ============ swapTokensForExactTokens TESTS ============

    function test_SwapTokensForExactTokens() public {
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(weth);

        uint256 amountOut = 1 ether;
        uint256[] memory expectedAmounts = router.getAmountsIn(amountOut, path);
        uint256 amountInMax = (expectedAmounts[0] * 105) / 100; // 5% buffer

        uint256 wethBefore = weth.balanceOf(address(this));

        router.swapTokensForExactTokens(
            amountOut,
            amountInMax,
            path,
            address(this),
            block.timestamp
        );

        uint256 wethAfter = weth.balanceOf(address(this));
        assertEq(
            wethAfter - wethBefore,
            amountOut,
            "Should receive exact output"
        );
    }

    function testRevert_SwapTokensForExactTokens_ExcessiveInput() public {
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(weth);

        uint256 amountOut = 1 ether;
        uint256 tooLowMax = 1 * 10 ** 18; // Way too low

        vm.expectRevert("Router: EXCESSIVE_INPUT_AMOUNT");
        router.swapTokensForExactTokens(
            amountOut,
            tooLowMax,
            path,
            address(this),
            block.timestamp
        );
    }

    // ============ addLiquidityETH TESTS ============

    function test_AddLiquidityETH() public {
        ERC20Mock tokenB = new ERC20Mock("Token B", "TKB", 18);
        tokenB.mint(address(this), 10_000 * 10 ** 18);
        tokenB.approve(address(router), type(uint256).max);

        uint256 ethBefore = address(this).balance;

        (uint256 amountToken, uint256 amountETH, uint256 liquidity) = router
            .addLiquidityETH{value: 10 ether}(
            address(tokenB),
            1000 * 10 ** 18, // 1000 tokens
            0,
            0,
            address(this),
            block.timestamp
        );

        assertGt(amountToken, 0, "Should use tokens");
        assertGt(amountETH, 0, "Should use ETH");
        assertGt(liquidity, 0, "Should receive LP tokens");
        assertEq(
            address(this).balance,
            ethBefore - amountETH,
            "Should use correct ETH"
        );
    }

    function test_AddLiquidityETH_RefundsExcess() public {
        ERC20Mock tokenB = new ERC20Mock("Token B", "TKB", 18);
        tokenB.mint(address(this), 10_000 * 10 ** 18);
        tokenB.approve(address(router), type(uint256).max);

        // First add liquidity to set price
        router.addLiquidityETH{value: 10 ether}(
            address(tokenB),
            1000 * 10 ** 18,
            0,
            0,
            address(this),
            block.timestamp
        );

        // Add more with excess ETH
        uint256 ethBefore = address(this).balance;

        router.addLiquidityETH{value: 20 ether}( // Send way more than needed
            address(tokenB),
            100 * 10 ** 18, // Only 100 tokens
            0,
            0,
            address(this),
            block.timestamp
        );

        // Should get refund (not use all 20 ETH)
        uint256 ethUsed = ethBefore - address(this).balance;
        assertLt(ethUsed, 20 ether, "Should not use all ETH");
    }

    // ============ swapExactETHForTokens TESTS ============

    function test_SwapExactETHForTokens() public {
        address[] memory path = new address[](2);
        path[0] = address(weth);
        path[1] = address(tokenA);

        uint256 tokensBefore = tokenA.balanceOf(address(this));

        uint256[] memory amounts = router.swapExactETHForTokens{value: 1 ether}(
            0,
            path,
            address(this),
            block.timestamp
        );

        uint256 tokensAfter = tokenA.balanceOf(address(this));
        assertEq(
            tokensAfter - tokensBefore,
            amounts[1],
            "Should receive calculated amount"
        );
        assertGt(amounts[1], 0, "Should receive tokens");
    }

    function testRevert_SwapExactETHForTokens_InvalidPath() public {
        address[] memory path = new address[](2);
        path[0] = address(tokenA); // Not WETH
        path[1] = address(weth);

        vm.expectRevert("Router: INVALID_PATH");
        router.swapExactETHForTokens{value: 1 ether}(
            0,
            path,
            address(this),
            block.timestamp
        );
    }

    // ============ swapExactTokensForETH TESTS ============

    function test_SwapExactTokensForETH() public {
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(weth);

        uint256 ethBefore = address(this).balance;
        uint256 amountIn = 100 * 10 ** 18;

        uint256[] memory amounts = router.swapExactTokensForETH(
            amountIn,
            0,
            path,
            address(this),
            block.timestamp
        );

        uint256 ethAfter = address(this).balance;
        assertEq(
            ethAfter - ethBefore,
            amounts[1],
            "Should receive calculated ETH"
        );
        assertGt(amounts[1], 0, "Should receive ETH");
    }

    // ============ swapETHForExactTokens TESTS ============

    function test_SwapETHForExactTokens() public {
        address[] memory path = new address[](2);
        path[0] = address(weth);
        path[1] = address(tokenA);

        uint256 exactTokensOut = 100 * 10 ** 18;
        uint256 ethBefore = address(this).balance;
        uint256 tokensBefore = tokenA.balanceOf(address(this));

        uint256[] memory amounts = router.swapETHForExactTokens{
            value: 10 ether
        }(exactTokensOut, path, address(this), block.timestamp);

        uint256 tokensAfter = tokenA.balanceOf(address(this));
        assertEq(
            tokensAfter - tokensBefore,
            exactTokensOut,
            "Should receive exact tokens"
        );

        // Check refund worked (shouldn't use all 10 ETH)
        uint256 ethUsed = ethBefore - address(this).balance;
        assertEq(ethUsed, amounts[0], "Should only use calculated ETH");
    }

    // ============ swapTokensForExactETH TESTS ============

    function test_SwapTokensForExactETH() public {
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(weth);

        uint256 exactETHOut = 1 ether;
        uint256 ethBefore = address(this).balance;

        router.swapTokensForExactETH(
            exactETHOut,
            type(uint256).max,
            path,
            address(this),
            block.timestamp
        );

        uint256 ethAfter = address(this).balance;
        assertEq(ethAfter - ethBefore, exactETHOut, "Should receive exact ETH");
    }

    // ============ removeLiquidityETH TESTS ============

    function test_RemoveLiquidityETH() public {
        // First add liquidity with ETH
        ERC20Mock tokenB = new ERC20Mock("Token B", "TKB", 18);
        tokenB.mint(address(this), 10_000 * 10 ** 18);
        tokenB.approve(address(router), type(uint256).max);

        (, , uint256 liquidity) = router.addLiquidityETH{value: 10 ether}(
            address(tokenB),
            1000 * 10 ** 18,
            0,
            0,
            address(this),
            block.timestamp
        );

        // Approve and remove
        address pairAddress = factory.getPair(address(tokenB), address(weth));
        Pair lpToken = Pair(pairAddress);
        lpToken.approve(address(router), liquidity);

        uint256 ethBefore = address(this).balance;
        uint256 tokensBefore = tokenB.balanceOf(address(this));

        (uint256 amountToken, uint256 amountETH) = router.removeLiquidityETH(
            address(tokenB),
            liquidity,
            0,
            0,
            address(this),
            block.timestamp
        );

        assertGt(amountToken, 0, "Should receive tokens");
        assertGt(amountETH, 0, "Should receive ETH");
        assertEq(
            tokenB.balanceOf(address(this)),
            tokensBefore + amountToken,
            "Token balance should increase"
        );
        assertEq(
            address(this).balance,
            ethBefore + amountETH,
            "ETH balance should increase"
        );
    }
}
