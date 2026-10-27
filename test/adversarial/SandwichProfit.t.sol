// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../../src/Factory.sol";
import "../../src/Router.sol";
import "../../src/Pair.sol";
import "../../src/WETH9.sol";
import "../../src/test/mocks/ERC20Mock.sol";

/// @notice Sandwich economics: the victim side is covered in
/// MarketConditions (victim gets less + slippage protection). This file pins
/// the attacker's side — the sandwich must be profitable, otherwise the
/// threat model overstates it. The clean baseline runs on a separate,
/// identical fresh pool (no magic constants).
contract SandwichProfitTest is Test {
    Factory factory;
    Router router;
    WETH9 weth;

    address attacker = address(0xA774);
    address victim = address(0xB1C7);

    function setUp() public {
        weth = new WETH9();
        factory = new Factory();
        router = new Router(address(factory), address(weth));
    }

    function _freshPool(uint256 amt) internal returns (ERC20Mock tokenA, ERC20Mock tokenB) {
        tokenA = new ERC20Mock("Token A", "TKA", 18);
        tokenB = new ERC20Mock("Token B", "TKB", 18);
        tokenA.mint(address(this), amt * 2);
        tokenB.mint(address(this), amt * 2);
        tokenA.approve(address(router), type(uint256).max);
        tokenB.approve(address(router), type(uint256).max);
        router.addLiquidity(
            address(tokenA), address(tokenB), amt, amt, 0, 0, address(this), block.timestamp
        );
    }

    function _swapAB(ERC20Mock tokenA, ERC20Mock tokenB, address from, uint256 amountIn, address to)
        internal
        returns (uint256 out)
    {
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        uint256 before = tokenB.balanceOf(to);
        vm.prank(from);
        router.swapExactTokensForTokens(amountIn, 0, path, to, block.timestamp);
        out = tokenB.balanceOf(to) - before;
    }

    /// Attacker frontruns + backruns a victim swap and nets a profit,
    /// while the victim gets less than on an untouched pool.
    function test_SandwichIsProfitable() public {
        (ERC20Mock tokenA, ERC20Mock tokenB) = _freshPool(100_000 * 1e18);

        tokenA.mint(attacker, 100_000 * 1e18);
        tokenA.mint(victim, 10_000 * 1e18);
        vm.prank(attacker);
        tokenA.approve(address(router), type(uint256).max);
        vm.prank(victim);
        tokenA.approve(address(router), type(uint256).max);

        // Frontrun: attacker buys B with 20k A.
        uint256 attackerBBefore = tokenB.balanceOf(attacker);
        _swapAB(tokenA, tokenB, attacker, 20_000 * 1e18, attacker);
        uint256 attackerB = tokenB.balanceOf(attacker) - attackerBBefore;

        // Victim swap executes at the manipulated price.
        uint256 victimOut = _swapAB(tokenA, tokenB, victim, 10_000 * 1e18, victim);

        // Backrun: attacker sells the B back for A.
        address[] memory pathBA = new address[](2);
        pathBA[0] = address(tokenB);
        pathBA[1] = address(tokenA);
        vm.prank(attacker);
        tokenB.approve(address(router), attackerB);
        uint256 attackerABefore = tokenA.balanceOf(attacker);
        vm.prank(attacker);
        router.swapExactTokensForTokens(attackerB, 0, pathBA, attacker, block.timestamp);
        uint256 attackerA = tokenA.balanceOf(attacker) - attackerABefore;

        uint256 attackerSpent = 20_000 * 1e18;
        assertGt(attackerA, attackerSpent, "sandwich must be profitable for the attacker");
        emit log_named_uint("attackerProfit", attackerA - attackerSpent);

        // Victim got less than an identical swap on an untouched pool.
        (ERC20Mock cleanA, ERC20Mock cleanB) = _freshPool(100_000 * 1e18);
        cleanA.mint(address(this), 10_000 * 1e18);
        address[] memory cleanPath = new address[](2);
        cleanPath[0] = address(cleanA);
        cleanPath[1] = address(cleanB);
        uint256 cleanBefore = cleanB.balanceOf(address(this));
        router.swapExactTokensForTokens(10_000 * 1e18, 0, cleanPath, address(this), block.timestamp);
        uint256 cleanOut = cleanB.balanceOf(address(this)) - cleanBefore;
        assertLt(victimOut, cleanOut, "victim got less than clean swap");
    }
}
