// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "../src/Factory.sol";
import "../src/Router.sol";
import "../src/Oracle.sol";
import "../src/WETH9.sol";

/// @notice Infrastructure-only deployment: WETH, Factory, Router, Oracle.
/// No test tokens, no liquidity seeding (see script/SeedLocal.s.sol).
/// Requires an explicit signer (PRIVATE_KEY); never falls back silently.
contract DeployScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        address weth;
        if (block.chainid == 31337) {
            // Local dev chain: deploy a throwaway WETH9.
            vm.startBroadcast(deployerPrivateKey);
            weth = address(new WETH9());
        } else {
            // Any other chain: use the operator-configured canonical WETH.
            // Never deploy a lookalike WETH on mainnet/testnet (W-01).
            weth = vm.envAddress("WETH_ADDRESS");
            require(weth.code.length > 0, "Deploy: WETH has no code");
            vm.startBroadcast(deployerPrivateKey);
        }

        Factory factory = new Factory();
        Router router = new Router(address(factory), weth);
        Oracle oracle = new Oracle(address(factory));

        // Post-deploy sanity checks (D-04).
        require(router.factory() == address(factory), "Deploy: factory mismatch");
        require(router.WETH() == weth, "Deploy: WETH mismatch");
        require(oracle.factory() == address(factory), "Deploy: oracle factory mismatch");

        console.log("Deployer:", deployer);
        console.log("Chain ID:", block.chainid);
        console.log("WETH:", weth);
        console.log("Factory:", address(factory));
        console.log("Router:", address(router));
        console.log("Oracle:", address(oracle));

        vm.stopBroadcast();
    }
}
