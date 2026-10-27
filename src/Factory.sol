// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Pair.sol";

contract Factory {
    mapping(address => mapping(address => address)) public getPair;
    address[] public allPairs;

    event PairCreated(address indexed token0, address indexed token1, address pair, uint);

    function createPair(address tokenA, address tokenB) external returns (address pair) {
        require(tokenA != tokenB, "Factory: IDENTICAL_ADDRESSES");
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), "Factory: ZERO_ADDRESS");
        require(tokenA.code.length > 0 && tokenB.code.length > 0, "Factory: INVALID_TOKEN");
        require(getPair[token0][token1] == address(0), "Factory: PAIR_EXISTS");

        bytes memory bytecode = type(Pair).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        assembly {
            pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        require(pair != address(0) && pair.code.length > 0, "Factory: PAIR_DEPLOY_FAILED");

        Pair(pair).initialize(token0, token1);

        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair;
        allPairs.push(pair);
        emit PairCreated(token0, token1, pair, allPairs.length);
    }

    function allPairsLength() external view returns (uint) {
        return allPairs.length;
    }

    /// @notice Predict the CREATE2 address for a token pair (single source of
    /// truth shared with off-chain integrations and tests).
    function computePairAddress(address tokenA, address tokenB) public view returns (address pair) {
        require(tokenA != tokenB, "Factory: IDENTICAL_ADDRESSES");
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), "Factory: ZERO_ADDRESS");
        pair = address(
            uint160(
                uint(
                    keccak256(
                        abi.encodePacked(
                            hex"ff",
                            address(this),
                            keccak256(abi.encodePacked(token0, token1)),
                            keccak256(type(Pair).creationCode)
                        )
                    )
                )
            )
        );
    }
}
