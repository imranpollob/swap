// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Pair.sol";
import "solmate/utils/FixedPointMathLib.sol";

/**
 * @title Oracle
 * @notice Time-Weighted Average Price (TWAP) oracle for AMM pairs
 * @dev Uses cumulative prices from pair contracts to calculate manipulation-resistant prices
 *
 * ## How TWAP Works
 * 1. Each block, the pair accumulates price0CumulativeLast and price1CumulativeLast
 * 2. To get TWAP: (priceCumulativeEnd - priceCumulativeStart) / timeElapsed
 * 3. This makes price manipulation expensive (must sustain manipulation for entire period)
 */
contract Oracle {
    using FixedPointMathLib for uint256;

    struct Observation {
        uint256 timestamp;
        uint256 price0Cumulative;
        uint256 price1Cumulative;
    }

    // Pair address => Array of price observations
    mapping(address => Observation[]) public observations;

    // Minimum observation period for TWAP calculation
    uint256 public constant MIN_TWAP_PERIOD = 1 minutes;

    // Maximum observation age before considered stale
    uint256 public constant MAX_OBSERVATION_AGE = 1 days;

    event ObservationRecorded(
        address indexed pair,
        uint256 timestamp,
        uint256 price0Cumulative,
        uint256 price1Cumulative
    );

    /**
     * @notice Record a new price observation for a pair
     * @param pair Address of the pair to observe
     * @dev Should be called regularly (e.g., every block or every few minutes)
     */
    function update(address pair) external {
        (
            uint256 price0Cumulative,
            uint256 price1Cumulative,
            uint32 blockTimestamp
        ) = _currentCumulativePrices(pair);

        Observation[] storage obs = observations[pair];

        // Only record if time has passed since last observation
        if (obs.length == 0 || obs[obs.length - 1].timestamp < blockTimestamp) {
            obs.push(
                Observation({
                    timestamp: blockTimestamp,
                    price0Cumulative: price0Cumulative,
                    price1Cumulative: price1Cumulative
                })
            );

            emit ObservationRecorded(
                pair,
                blockTimestamp,
                price0Cumulative,
                price1Cumulative
            );
        }
    }

    /**
     * @notice Get the TWAP for token0 in terms of token1
     * @param pair Address of the pair
     * @param period Time period in seconds for TWAP calculation
     * @return price0Average The average price of token0 in token1 (fixed point Q112.112)
     */
    function consult(
        address pair,
        uint256 period
    ) external view returns (uint256 price0Average) {
        require(period >= MIN_TWAP_PERIOD, "Oracle: PERIOD_TOO_SHORT");

        Observation[] storage obs = observations[pair];
        require(obs.length >= 2, "Oracle: INSUFFICIENT_OBSERVATIONS");

        // Find observations spanning the requested period
        uint256 targetTime = block.timestamp - period;

        // Get the most recent observation
        Observation storage latestObs = obs[obs.length - 1];
        require(
            latestObs.timestamp <= block.timestamp,
            "Oracle: OBSERVATION_IN_FUTURE"
        );

        // Find the oldest observation that's at least 'period' old
        Observation storage oldestObs = obs[0];
        for (uint i = obs.length - 1; i > 0; i--) {
            if (obs[i - 1].timestamp <= targetTime) {
                oldestObs = obs[i - 1];
                break;
            }
        }

        uint256 timeElapsed = latestObs.timestamp - oldestObs.timestamp;
        require(
            timeElapsed >= MIN_TWAP_PERIOD,
            "Oracle: INSUFFICIENT_ELAPSED_TIME"
        );

        // Calculate TWAP (overflow is desired for cumulative price)
        unchecked {
            price0Average =
                (latestObs.price0Cumulative - oldestObs.price0Cumulative) /
                timeElapsed;
        }
    }

    /**
     * @notice Get both TWAP prices
     * @param pair Address of the pair
     * @param period Time period in seconds
     * @return price0Average Price of token0 in token1
     * @return price1Average Price of token1 in token0
     */
    function consultBoth(
        address pair,
        uint256 period
    ) external view returns (uint256 price0Average, uint256 price1Average) {
        require(period >= MIN_TWAP_PERIOD, "Oracle: PERIOD_TOO_SHORT");

        Observation[] storage obs = observations[pair];
        require(obs.length >= 2, "Oracle: INSUFFICIENT_OBSERVATIONS");

        uint256 targetTime = block.timestamp - period;

        Observation storage latestObs = obs[obs.length - 1];
        Observation storage oldestObs = obs[0];

        for (uint i = obs.length - 1; i > 0; i--) {
            if (obs[i - 1].timestamp <= targetTime) {
                oldestObs = obs[i - 1];
                break;
            }
        }

        uint256 timeElapsed = latestObs.timestamp - oldestObs.timestamp;
        require(
            timeElapsed >= MIN_TWAP_PERIOD,
            "Oracle: INSUFFICIENT_ELAPSED_TIME"
        );

        unchecked {
            price0Average =
                (latestObs.price0Cumulative - oldestObs.price0Cumulative) /
                timeElapsed;
            price1Average =
                (latestObs.price1Cumulative - oldestObs.price1Cumulative) /
                timeElapsed;
        }
    }

    /**
     * @notice Get the current spot price for comparison with TWAP
     * @param pair Address of the pair
     * @return price0Spot Current spot price of token0 in token1
     */
    function getSpotPrice(
        address pair
    ) external view returns (uint256 price0Spot) {
        (uint112 reserve0, uint112 reserve1, ) = Pair(pair).getReserves();
        require(reserve0 > 0 && reserve1 > 0, "Oracle: NO_RESERVES");

        // Price with 18 decimal precision
        price0Spot = (uint256(reserve1) * 1e18) / uint256(reserve0);
    }

    /**
     * @notice Check if price has deviated significantly from TWAP (potential manipulation)
     * @param pair Address of the pair
     * @param period TWAP period
     * @param maxDeviation Maximum allowed deviation in basis points (10000 = 100%)
     * @return isManipulated True if current price deviates more than maxDeviation from TWAP
     */
    function isPriceManipulated(
        address pair,
        uint256 period,
        uint256 maxDeviation
    ) external view returns (bool isManipulated) {
        (uint112 reserve0, uint112 reserve1, ) = Pair(pair).getReserves();
        if (reserve0 == 0 || reserve1 == 0) return true;

        Observation[] storage obs = observations[pair];
        if (obs.length < 2) return false; // Can't determine manipulation without history

        uint256 spotPrice = (uint256(reserve1) * 1e18) / uint256(reserve0);

        // Get TWAP
        uint256 targetTime = block.timestamp - period;
        Observation storage latestObs = obs[obs.length - 1];
        Observation storage oldestObs = obs[0];

        for (uint i = obs.length - 1; i > 0; i--) {
            if (obs[i - 1].timestamp <= targetTime) {
                oldestObs = obs[i - 1];
                break;
            }
        }

        uint256 timeElapsed = latestObs.timestamp - oldestObs.timestamp;
        if (timeElapsed < MIN_TWAP_PERIOD) return false;

        uint256 twapPrice;
        unchecked {
            twapPrice =
                (latestObs.price0Cumulative - oldestObs.price0Cumulative) /
                timeElapsed;
        }

        // Convert TWAP to same scale as spot price (18 decimals)
        // Q112.112 to 18 decimals: 2^112 / 1e18 ≈ 5192296858534827
        uint256 Q112_DIV_1E18 = 5192296858534827;
        twapPrice = twapPrice / Q112_DIV_1E18;

        // Calculate deviation
        uint256 deviation;
        if (spotPrice > twapPrice) {
            deviation = ((spotPrice - twapPrice) * 10000) / twapPrice;
        } else {
            deviation = ((twapPrice - spotPrice) * 10000) / twapPrice;
        }

        isManipulated = deviation > maxDeviation;
    }

    /**
     * @notice Get number of observations for a pair
     * @param pair Address of the pair
     * @return count Number of recorded observations
     */
    function observationCount(
        address pair
    ) external view returns (uint256 count) {
        return observations[pair].length;
    }

    /**
     * @notice Get latest observation for a pair
     * @param pair Address of the pair
     * @return obs The most recent observation
     */
    function latestObservation(
        address pair
    ) external view returns (Observation memory obs) {
        require(observations[pair].length > 0, "Oracle: NO_OBSERVATIONS");
        return observations[pair][observations[pair].length - 1];
    }

    /**
     * @dev Helper to get current cumulative prices from pair
     */
    function _currentCumulativePrices(
        address pair
    )
        internal
        view
        returns (
            uint256 price0Cumulative,
            uint256 price1Cumulative,
            uint32 blockTimestamp
        )
    {
        blockTimestamp = uint32(block.timestamp);
        (uint112 reserve0, uint112 reserve1, uint32 timestampLast) = Pair(pair)
            .getReserves();

        // If time has elapsed since the last update on the pair,
        // we need to accumulate the price since then
        if (timestampLast != blockTimestamp && reserve0 > 0 && reserve1 > 0) {
            uint32 timeElapsed = blockTimestamp - timestampLast;

            // Calculate price in Q112.112 format
            uint256 price0 = (uint256(reserve1) << 112) / reserve0;
            uint256 price1 = (uint256(reserve0) << 112) / reserve1;

            price0Cumulative = price0 * timeElapsed;
            price1Cumulative = price1 * timeElapsed;
        }
    }
}
