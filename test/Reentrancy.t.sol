// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/Factory.sol";
import "../src/Router.sol";
import "../src/Pair.sol";
import "../src/WETH9.sol";
import "../src/test/mocks/ERC20Mock.sol";

/// @notice ERC20 that tries to reenter its pair from inside a transfer
/// callback (swap/burn payout path) and records the outcome.
contract ReentrantERC20 is ERC20Mock {
    Pair public target;
    bool public reentered;
    bool public blocked;
    string public blockReason;

    constructor() ERC20Mock("Reentrant", "RNT", 18) { }

    function setTarget(Pair p) external {
        target = p;
    }

    function transfer(address to, uint256 wad) public override returns (bool) {
        if (address(target) != address(0) && !blocked && !reentered) {
            // The pair lock is checked before any swap logic, so this
            // reverts with Pair: LOCKED regardless of amounts.
            try target.swap(1, 0, address(this)) {
                reentered = true;
            } catch Error(string memory reason) {
                blocked = true;
                blockReason = reason;
            } catch {
                blocked = true;
            }
        }
        return super.transfer(to, wad);
    }
}

/// @notice ETH recipient that tries to reenter the router from receive().
contract ReentrantRecipient {
    Router public router;
    address[] public path;
    bool public reentered;
    bool public blocked;

    constructor(Router r, address[] memory p) {
        router = r;
        path = p;
    }

    receive() external payable {
        if (!blocked && !reentered) {
            try router.swapExactTokensForTokens(1 ether, 0, path, address(this), block.timestamp) {
                reentered = true;
            } catch {
                blocked = true;
            }
        }
    }
}

/// @notice R-01: reentrancy attempts against Pair and Router must fail.
contract ReentrancyTest is Test {
    Factory factory;
    Router router;
    WETH9 weth;
    ReentrantERC20 rnt;
    ERC20Mock tokenB;
    Pair pair;

    function setUp() public {
        weth = new WETH9();
        factory = new Factory();
        router = new Router(address(factory), address(weth));
        rnt = new ReentrantERC20();
        tokenB = new ERC20Mock("Token B", "TKB", 18);

        rnt.mint(address(this), 1_000_000 * 1e18);
        tokenB.mint(address(this), 1_000_000 * 1e18);
        rnt.approve(address(router), type(uint256).max);
        tokenB.approve(address(router), type(uint256).max);

        router.addLiquidity(
            address(rnt),
            address(tokenB),
            100_000 * 1e18,
            100_000 * 1e18,
            0,
            0,
            address(this),
            block.timestamp
        );
        pair = Pair(factory.getPair(address(rnt), address(tokenB)));
        rnt.setTarget(pair);
    }

    function test_ReentrantTokenCannotReenterPair() public {
        // Swap B -> RNT: the pair sends RNT out, firing the malicious
        // transfer callback while the pair lock is held.
        address[] memory path = new address[](2);
        path[0] = address(tokenB);
        path[1] = address(rnt);
        router.swapExactTokensForTokens(1000 * 1e18, 0, path, address(this), block.timestamp);

        assertTrue(rnt.blocked(), "R-01: reentrant pair call must revert");
        assertFalse(rnt.reentered(), "R-01: reentrancy must not succeed");
        assertEq(rnt.blockReason(), "Pair: LOCKED");
    }

    function test_ReentrantRecipientCannotReenterRouter() public {
        // Pool for the reentrant hop + ETH payout leg.
        vm.deal(address(this), 2000 ether);
        weth.deposit{ value: 1000 ether }();
        weth.approve(address(router), type(uint256).max);
        router.addLiquidity(
            address(tokenB),
            address(weth),
            10_000 * 1e18,
            1000 ether,
            0,
            0,
            address(this),
            block.timestamp
        );

        address[] memory reenterPath = new address[](2);
        reenterPath[0] = address(tokenB);
        reenterPath[1] = address(weth);
        ReentrantRecipient recipient = new ReentrantRecipient(router, reenterPath);
        tokenB.mint(address(recipient), 10_000 * 1e18);
        vm.prank(address(recipient));
        tokenB.approve(address(router), type(uint256).max);

        // Pay the malicious recipient ETH through the router; its receive()
        // tries to swap again while the router lock is held.
        address[] memory path = new address[](2);
        path[0] = address(tokenB);
        path[1] = address(weth);
        router.swapExactTokensForETH(
            1000 * 1e18, 0, path, payable(address(recipient)), block.timestamp
        );

        assertTrue(recipient.blocked(), "R-01: reentrant router call must revert");
        assertFalse(recipient.reentered(), "R-01: router reentrancy must not succeed");
    }
}
