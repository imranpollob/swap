// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/Factory.sol";
import "../src/Pair.sol";
import "../src/WETH9.sol";
import "../src/test/mocks/ERC20Mock.sol";

/// @notice F-01..F-04: factory deployment guards and CREATE2 consistency.
contract FactoryTest is Test {
    Factory factory;
    ERC20Mock tokenA;
    ERC20Mock tokenB;

    function setUp() public {
        factory = new Factory();
        tokenA = new ERC20Mock("Token A", "TKA", 18);
        tokenB = new ERC20Mock("Token B", "TKB", 18);
    }

    function test_CreatePair() public {
        address pair = factory.createPair(address(tokenA), address(tokenB));
        assertTrue(pair != address(0));
        assertTrue(pair.code.length > 0, "F-01: deployed pair must have code");
        assertEq(factory.getPair(address(tokenA), address(tokenB)), pair);
        assertEq(factory.getPair(address(tokenB), address(tokenA)), pair);
        assertEq(factory.allPairsLength(), 1);
        assertEq(factory.allPairs(0), pair);
        // Pair is initialized exactly once, by the factory.
        assertEq(Pair(pair).token0() < Pair(pair).token1(), true);
        assertEq(Pair(pair).factory(), address(factory));
    }

    function test_ComputePairAddressMatches() public {
        address predicted = factory.computePairAddress(address(tokenA), address(tokenB));
        // Order-independent prediction.
        assertEq(predicted, factory.computePairAddress(address(tokenB), address(tokenA)));
        address pair = factory.createPair(address(tokenA), address(tokenB));
        assertEq(predicted, pair, "F-04: prediction must match deployment");
    }

    function test_Revert_DuplicatePair() public {
        factory.createPair(address(tokenA), address(tokenB));
        vm.expectRevert("Factory: PAIR_EXISTS");
        factory.createPair(address(tokenB), address(tokenA));
    }

    function test_Revert_IdenticalTokens() public {
        vm.expectRevert("Factory: IDENTICAL_ADDRESSES");
        factory.createPair(address(tokenA), address(tokenA));
    }

    function test_Revert_ZeroAddress() public {
        vm.expectRevert("Factory: ZERO_ADDRESS");
        factory.createPair(address(tokenA), address(0));
    }

    function test_Revert_NonContractToken() public {
        // EOAs and empty accounts cannot be pairs' underlying tokens.
        vm.expectRevert("Factory: INVALID_TOKEN");
        factory.createPair(address(tokenA), address(0x1234));
    }
}
