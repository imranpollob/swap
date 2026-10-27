// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../../src/Factory.sol";
import "../../src/Router.sol";
import "../../src/Pair.sol";
import "../../src/WETH9.sol";
import "../../src/test/mocks/ERC20Mock.sol";

/// @notice 1% fee-on-transfer token (fee burned). The protocol does not
/// support fee tokens: deposits skew and input-fee swaps break the K check.
/// These tests pin the documented failure modes.
contract FeeToken is ERC20Mock {
    uint256 public constant FEE_BPS = 100; // 1%

    constructor() ERC20Mock("Fee Token", "FEE", 18) { }

    function transfer(address to, uint256 wad) public override returns (bool) {
        uint256 fee = (wad * FEE_BPS) / 10000;
        if (fee > 0) _burn(msg.sender, fee);
        return super.transfer(to, wad - fee);
    }

    function transferFrom(address from, address to, uint256 wad) public override returns (bool) {
        uint256 fee = (wad * FEE_BPS) / 10000;
        uint256 allowed = allowance[from][msg.sender];
        if (from != msg.sender && allowed != type(uint256).max) {
            require(allowed >= wad, "FEE: ALLOWANCE");
            allowance[from][msg.sender] = allowed - wad;
        }
        if (fee > 0) _burn(from, fee);
        // Net movement, mirroring solmate's allowance/balance handling.
        balanceOf[from] -= (wad - fee);
        unchecked {
            balanceOf[to] += (wad - fee);
        }
        emit Transfer(from, to, wad - fee);
        return true;
    }
}

/// @notice USDT-style token: transfer/transferFrom return no data.
/// SafeTransferLib tolerates empty returndata, so these must work.
contract NoReturnToken {
    string public name = "No Return";
    string public symbol = "NRT";
    uint8 public decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 wad);
    event Approval(address indexed src, address indexed guy, uint256 wad);

    function mint(address to, uint256 wad) external {
        balanceOf[to] += wad;
        totalSupply += wad;
        emit Transfer(address(0), to, wad);
    }

    function approve(address guy, uint256 wad) external {
        allowance[msg.sender][guy] = wad;
        emit Approval(msg.sender, guy, wad);
    }

    function transfer(address to, uint256 wad) external {
        require(balanceOf[msg.sender] >= wad, "NRT: BALANCE");
        unchecked {
            balanceOf[msg.sender] -= wad;
            balanceOf[to] += wad;
        }
        emit Transfer(msg.sender, to, wad);
    }

    function transferFrom(address from, address to, uint256 wad) external {
        uint256 allowed = allowance[from][msg.sender];
        if (from != msg.sender && allowed != type(uint256).max) {
            require(allowed >= wad, "NRT: ALLOWANCE");
            allowance[from][msg.sender] = allowed - wad;
        }
        require(balanceOf[from] >= wad, "NRT: BALANCE");
        unchecked {
            balanceOf[from] -= wad;
            balanceOf[to] += wad;
        }
        emit Transfer(from, to, wad);
    }
}

/// @notice Non-standard and low-decimal token behavior.
contract NonStandardTokensTest is Test {
    Factory factory;
    Router router;
    WETH9 weth;

    function setUp() public {
        weth = new WETH9();
        factory = new Factory();
        router = new Router(address(factory), address(weth));
    }

    function test_FeeToken_SkewsDeposit() public {
        FeeToken fee = new FeeToken();
        ERC20Mock tokenB = new ERC20Mock("Token B", "TKB", 18);
        fee.mint(address(this), 1_000_000 * 1e18);
        tokenB.mint(address(this), 1_000_000 * 1e18);
        fee.approve(address(router), type(uint256).max);
        tokenB.approve(address(router), type(uint256).max);

        // Succeeds, but the pool receives 1% less fee-token than quoted:
        // liquidity is priced on actual balances, not intentions.
        router.addLiquidity(
            address(fee),
            address(tokenB),
            100_000 * 1e18,
            100_000 * 1e18,
            0,
            0,
            address(this),
            block.timestamp
        );
        Pair pool = Pair(factory.getPair(address(fee), address(tokenB)));
        (uint112 r0, uint112 r1,) = pool.getReserves();
        (uint256 feeReserve, uint256 otherReserve) =
            address(fee) == pool.token0() ? (uint256(r0), uint256(r1)) : (uint256(r1), uint256(r0));
        assertEq(feeReserve, 99_000 * 1e18, "pool got net of fee");
        assertEq(otherReserve, 100_000 * 1e18);
    }

    function test_FeeToken_InputSwapReverts() public {
        FeeToken fee = new FeeToken();
        ERC20Mock tokenB = new ERC20Mock("Token B", "TKB", 18);
        fee.mint(address(this), 1_000_000 * 1e18);
        tokenB.mint(address(this), 1_000_000 * 1e18);
        fee.approve(address(router), type(uint256).max);
        tokenB.approve(address(router), type(uint256).max);
        router.addLiquidity(
            address(fee),
            address(tokenB),
            100_000 * 1e18,
            100_000 * 1e18,
            0,
            0,
            address(this),
            block.timestamp
        );

        // Fee on the input leg: the pair receives less than the router
        // assumed, so the K check fails. Documented unsupported behavior.
        address[] memory path = new address[](2);
        path[0] = address(fee);
        path[1] = address(tokenB);
        vm.expectRevert("Pair: K");
        router.swapExactTokensForTokens(1000 * 1e18, 0, path, address(this), block.timestamp);
    }

    function test_FeeToken_OutputSwapShortchanges() public {
        FeeToken fee = new FeeToken();
        ERC20Mock tokenB = new ERC20Mock("Token B", "TKB", 18);
        fee.mint(address(this), 1_000_000 * 1e18);
        tokenB.mint(address(this), 1_000_000 * 1e18);
        fee.approve(address(router), type(uint256).max);
        tokenB.approve(address(router), type(uint256).max);
        router.addLiquidity(
            address(fee),
            address(tokenB),
            100_000 * 1e18,
            100_000 * 1e18,
            0,
            0,
            address(this),
            block.timestamp
        );

        // Fee on the output leg: K holds (pair sent the full amount), but
        // the recipient is short-changed by the token itself.
        address[] memory path = new address[](2);
        path[0] = address(tokenB);
        path[1] = address(fee);
        uint256[] memory quoted = router.getAmountsOut(1000 * 1e18, path);
        uint256 before = fee.balanceOf(address(this));
        router.swapExactTokensForTokens(1000 * 1e18, 0, path, address(this), block.timestamp);
        uint256 received = fee.balanceOf(address(this)) - before;
        assertLt(received, quoted[1], "fee token short-changes recipient");
        // Mirror the token's own rounding: fee = floor(amount * 1%), net = amount - fee.
        assertEq(received, quoted[1] - (quoted[1] * 100) / 10000, "exactly 1% fee");
    }

    function test_NoReturnToken_Works() public {
        NoReturnToken nrt = new NoReturnToken();
        ERC20Mock tokenB = new ERC20Mock("Token B", "TKB", 18);
        nrt.mint(address(this), 1_000_000 * 1e18);
        tokenB.mint(address(this), 1_000_000 * 1e18);
        nrt.approve(address(router), type(uint256).max);
        tokenB.approve(address(router), type(uint256).max);

        router.addLiquidity(
            address(nrt),
            address(tokenB),
            100_000 * 1e18,
            100_000 * 1e18,
            0,
            0,
            address(this),
            block.timestamp
        );

        address[] memory path = new address[](2);
        path[0] = address(nrt);
        path[1] = address(tokenB);
        uint256[] memory quoted = router.getAmountsOut(1000 * 1e18, path);
        uint256 before = tokenB.balanceOf(address(this));
        router.swapExactTokensForTokens(1000 * 1e18, 0, path, address(this), block.timestamp);
        assertEq(tokenB.balanceOf(address(this)) - before, quoted[1]);
    }

    function test_SixDecimal_FullCycle() public {
        ERC20Mock usdc = new ERC20Mock("USD Coin", "USDC", 6);
        ERC20Mock weth18 = new ERC20Mock("WETH18", "W18", 18);
        usdc.mint(address(this), 2_000_000 * 1e6);
        weth18.mint(address(this), 2_000_000 * 1e18);
        usdc.approve(address(router), type(uint256).max);
        weth18.approve(address(router), type(uint256).max);

        (,, uint256 liq) = router.addLiquidity(
            address(usdc),
            address(weth18),
            100_000 * 1e6,
            100_000 * 1e18,
            0,
            0,
            address(this),
            block.timestamp
        );
        assertGt(liq, 0, "6-decimal liquidity mints");

        address[] memory path = new address[](2);
        path[0] = address(usdc);
        path[1] = address(weth18);
        uint256 before = weth18.balanceOf(address(this));
        router.swapExactTokensForTokens(1000 * 1e6, 0, path, address(this), block.timestamp);
        assertGt(weth18.balanceOf(address(this)) - before, 0, "6-dec swap out");

        Pair pool = Pair(factory.getPair(address(usdc), address(weth18)));
        pool.approve(address(router), liq);
        (uint256 a0, uint256 a1) = router.removeLiquidity(
            address(usdc), address(weth18), liq, 0, 0, address(this), block.timestamp
        );
        assertGt(a0 + a1, 0, "6-dec removal pays out");
    }
}
