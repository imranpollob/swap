// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "solmate/tokens/ERC20.sol";
import "solmate/utils/SafeTransferLib.sol";
import "solmate/utils/FixedPointMathLib.sol";

contract Pair is ERC20 {
    using SafeTransferLib for ERC20;

    uint public constant MINIMUM_LIQUIDITY = 1000;

    address public factory;
    address public token0;
    address public token1;

    uint112 private reserve0;
    uint112 private reserve1;
    uint32 private blockTimestampLast;

    function min(uint x, uint y) internal pure returns (uint z) {
        z = x < y ? x : y;
    }

    uint private unlocked = 1;
    modifier lock() {
        require(unlocked == 1, "Pair: LOCKED");
        unlocked = 0;
        _;
        unlocked = 1;
    }

    event Mint(address indexed sender, uint amount0, uint amount1);
    event Burn(
        address indexed sender,
        uint amount0,
        uint amount1,
        address indexed to
    );
    event Swap(
        address indexed sender,
        uint amount0In,
        uint amount1In,
        uint amount0Out,
        uint amount1Out,
        address indexed to
    );
    event Sync(uint112 reserve0, uint112 reserve1);

    constructor() ERC20("Mini Swap Pair", "MINI-LP", 18) {
        factory = msg.sender;
    }

    function initialize(address _token0, address _token1) external {
        require(msg.sender == factory, "Pair: FORBIDDEN");
        token0 = _token0;
        token1 = _token1;
    }

    function getReserves()
        public
        view
        returns (
            uint112 _reserve0,
            uint112 _reserve1,
            uint32 _blockTimestampLast
        )
    {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
        _blockTimestampLast = blockTimestampLast;
    }

    function _update(
        uint balance0,
        uint balance1,
        uint112 _reserve0,
        uint112 _reserve1
    ) private {
        require(
            balance0 <= type(uint112).max && balance1 <= type(uint112).max,
            "Pair: OVERFLOW"
        );
        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);
        blockTimestampLast = uint32(block.timestamp);
        emit Sync(reserve0, reserve1);
    }

    function mint(address to) external lock returns (uint liquidity) {
        (uint112 _reserve0, uint112 _reserve1, ) = getReserves();
        uint balance0 = ERC20(token0).balanceOf(address(this));
        uint balance1 = ERC20(token1).balanceOf(address(this));
        uint amount0 = balance0 - _reserve0;
        uint amount1 = balance1 - _reserve1;

        if (totalSupply == 0) {
            liquidity =
                FixedPointMathLib.sqrt(amount0 * amount1) -
                MINIMUM_LIQUIDITY;
            _mint(address(0), MINIMUM_LIQUIDITY);
        } else {
            liquidity = min(
                (amount0 * totalSupply) / _reserve0,
                (amount1 * totalSupply) / _reserve1
            );
        }
        require(liquidity > 0, "Pair: INSUFFICIENT_LIQUIDITY_MINTED");
        _mint(to, liquidity);

        _update(balance0, balance1, _reserve0, _reserve1);
        emit Mint(msg.sender, amount0, amount1);
    }

    function burn(
        address to
    ) external lock returns (uint amount0, uint amount1) {
        (uint112 _reserve0, uint112 _reserve1, ) = getReserves();
        address _token0 = token0;
        address _token1 = token1;
        uint balance0 = ERC20(_token0).balanceOf(address(this));
        uint balance1 = ERC20(_token1).balanceOf(address(this));
        uint liquidity = balanceOf[address(this)];

        amount0 = (liquidity * balance0) / totalSupply;
        amount1 = (liquidity * balance1) / totalSupply;
        require(
            amount0 > 0 && amount1 > 0,
            "Pair: INSUFFICIENT_LIQUIDITY_BURNED"
        );

        _burn(address(this), liquidity);
        ERC20(_token0).safeTransfer(to, amount0);
        ERC20(_token1).safeTransfer(to, amount1);

        balance0 = ERC20(_token0).balanceOf(address(this));
        balance1 = ERC20(_token1).balanceOf(address(this));

        _update(balance0, balance1, _reserve0, _reserve1);
        emit Burn(msg.sender, amount0, amount1, to);
    }

    function swap(
        uint amount0Out,
        uint amount1Out,
        address to,
        bytes calldata data
    ) external lock {
        require(
            amount0Out > 0 || amount1Out > 0,
            "Pair: INSUFFICIENT_OUTPUT_AMOUNT"
        );
        (uint112 _reserve0, uint112 _reserve1, ) = getReserves();
        require(
            amount0Out < _reserve0 && amount1Out < _reserve1,
            "Pair: INSUFFICIENT_LIQUIDITY"
        );

        uint balance0;
        uint balance1;
        {
            address _token0 = token0;
            address _token1 = token1;
            require(to != _token0 && to != _token1, "Pair: INVALID_TO");
            if (amount0Out > 0) ERC20(_token0).safeTransfer(to, amount0Out);
            if (amount1Out > 0) ERC20(_token1).safeTransfer(to, amount1Out);

            balance0 = ERC20(_token0).balanceOf(address(this));
            balance1 = ERC20(_token1).balanceOf(address(this));
        }

        uint amount0In = balance0 > _reserve0 - amount0Out
            ? balance0 - (_reserve0 - amount0Out)
            : 0;
        uint amount1In = balance1 > _reserve1 - amount1Out
            ? balance1 - (_reserve1 - amount1Out)
            : 0;
        require(
            amount0In > 0 || amount1In > 0,
            "Pair: INSUFFICIENT_INPUT_AMOUNT"
        );

        {
            uint balance0Adjusted = balance0 * 1000 - amount0In * 3;
            uint balance1Adjusted = balance1 * 1000 - amount1In * 3;
            require(
                balance0Adjusted * balance1Adjusted >=
                    uint(_reserve0) * _reserve1 * 1000 ** 2,
                "Pair: K"
            );
        }

        _update(balance0, balance1, _reserve0, _reserve1);
        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
    }

    function skim(address to) external lock {
        address _token0 = token0;
        address _token1 = token1;
        ERC20(_token0).safeTransfer(
            to,
            ERC20(_token0).balanceOf(address(this)) - reserve0
        );
        ERC20(_token1).safeTransfer(
            to,
            ERC20(_token1).balanceOf(address(this)) - reserve1
        );
    }

    function sync() external lock {
        _update(
            ERC20(token0).balanceOf(address(this)),
            ERC20(token1).balanceOf(address(this)),
            reserve0,
            reserve1
        );
    }
}
