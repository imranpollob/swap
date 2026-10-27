// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "../src/Router.sol";
import "../src/WETH9.sol";
import "../src/test/mocks/ERC20Mock.sol";

/// @notice Local/testnet seeding ONLY: deploys a mock token and adds
/// token/WETH liquidity to an existing router deployment.
/// Refuses mainnet and non-allowlisted chains (D-02). Recipient, router,
/// and amounts are explicit environment inputs — never msg.sender-derived.
contract SeedLocalScript is Script {
    uint256 internal constant ANVIL = 31337;
    uint256 internal constant SEPOLIA = 11155111;
    uint256 internal constant ARBITRUM_SEPOLIA = 421614;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address recipient = vm.envAddress("SEED_RECIPIENT");
        require(block.chainid != 1, "Seed: MAINNET_FORBIDDEN");
        require(
            block.chainid == ANVIL || block.chainid == SEPOLIA || block.chainid == ARBITRUM_SEPOLIA,
            "Seed: CHAIN_NOT_ALLOWED"
        );

        Router router = Router(payable(vm.envAddress("ROUTER_ADDRESS")));
        address weth = router.WETH();
        require(weth.code.length > 0, "Seed: WETH has no code");

        address deployer = vm.addr(deployerPrivateKey);
        uint256 amountETH = vm.envOr("SEED_AMOUNT_ETH", uint256(100 ether));
        uint256 amountToken = vm.envOr("SEED_AMOUNT_TOKEN", uint256(5_000 ether));
        require(deployer.balance >= amountETH, "Seed: INSUFFICIENT_ETH_BALANCE");

        vm.startBroadcast(deployerPrivateKey);

        ERC20Mock token = new ERC20Mock("Test Token", "TKA", 18);
        token.mint(deployer, amountToken);
        token.approve(address(router), amountToken);
        IWETH(weth).deposit{ value: amountETH }();
        ERC20(weth).approve(address(router), amountETH);
        router.addLiquidity(
            address(token), weth, amountToken, amountETH, 0, 0, recipient, block.timestamp + 1000
        );

        console.log("Seed token:", address(token));
        console.log("Recipient:", recipient);

        vm.stopBroadcast();
    }
}
