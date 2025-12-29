// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "../src/Factory.sol";
import "../src/Router.sol";
import "../src/WETH9.sol";
import "../src/test/mocks/ERC20Mock.sol";

contract DeployScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envOr("PRIVATE_KEY", uint256(0));

        if (deployerPrivateKey != 0) {
            vm.startBroadcast(deployerPrivateKey);
        } else {
            vm.startBroadcast();
        }

        WETH9 weth = new WETH9();
        console.log("WETH9 deployed at:", address(weth));

        Factory factory = new Factory();
        console.log("Factory deployed at:", address(factory));

        Router router = new Router(address(factory), address(weth));
        console.log("Router deployed at:", address(router));

        // Deploy a test token
        ERC20Mock tokenA = new ERC20Mock("Test Token A", "TKA", 18);
        console.log("TestTokenA deployed at:", address(tokenA));
        tokenA.mint(msg.sender, 1_000_000 * 10 ** 18); // Mint TKA to deployer

        // S E E D   L I Q U I D I T Y
        // ---------------------------
        uint256 amountETH = 100 * 10 ** 18;
        uint256 amountToken = 5000 * 10 ** 18; // 1 ETH = 50 TKA

        // 1. Wrap ETH
        weth.deposit{value: amountETH}();

        // 2. Approve Router
        weth.approve(address(router), amountETH);
        tokenA.approve(address(router), amountToken);

        // 3. Add Liquidity
        router.addLiquidity(
            address(tokenA),
            address(weth),
            amountToken,
            amountETH,
            0,
            0,
            msg.sender,
            block.timestamp + 1000
        );
        console.log("Liquidity Added: 100 WETH + 5000 TKA");

        vm.stopBroadcast();
    }
}
