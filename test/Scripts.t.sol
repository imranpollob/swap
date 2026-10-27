// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../script/SeedLocal.s.sol";

/// @notice D-02: seed script must refuse mainnet and non-allowlisted chains.
contract SeedLocalTest is Test {
    SeedLocalScript seed;

    function setUp() public {
        vm.setEnv("PRIVATE_KEY", "1234");
        vm.setEnv("SEED_RECIPIENT", "0x0000000000000000000000000000000000001234");
        vm.setEnv("ROUTER_ADDRESS", "0x0000000000000000000000000000000000005678");
        seed = new SeedLocalScript();
    }

    function test_RefusesMainnet() public {
        vm.chainId(1);
        vm.expectRevert("Seed: MAINNET_FORBIDDEN");
        seed.run();
    }

    function test_RefusesDisallowedChain() public {
        vm.chainId(5); // Goerli: not in the seed allowlist.
        vm.expectRevert("Seed: CHAIN_NOT_ALLOWED");
        seed.run();
    }
}
