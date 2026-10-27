// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Pair.sol";
import "./Factory.sol";

/**
 * @title Oracle
 * @notice Time-Weighted Average Price (TWAP) oracle for AMM pairs.
 * @dev Uses cumulative prices from pair contracts to calculate manipulation-resistant prices.
 * Design (see docs/AUDIT_REPORT.md O-01..O-11):
 * - Fixed-size ring buffer (1024 observations) with binary search: consult gas
 *   is bounded (~10 SLOADs) no matter how long the oracle runs.
 * - Minimum observation interval (5 minutes): rate-limits permissionless
 *   `update` griefing and bounds cardinality.
 * - Freshness enforcement (1 hour): stale observations revert instead of
 *   silently pricing off old data.
 * - Full-window validation: consult reverts unless a full `period` of history
 *   exists; no silent window shortening.
 * - Fail-closed manipulation guard: every validation failure returns true.
 * - Factory provenance: only pairs created by the known factory are accepted.
 *
 * ## How TWAP Works
 * 1. Each observation stores the pair's cumulative prices at that timestamp.
 * 2. TWAP = (cumulativeEnd - cumulativeStart) / timeElapsed.
 * 3. Manipulation must be sustained over the whole window to move the average.
 *
 * ## Units
 * - `consult` / `consultBoth` return Q112.112 raw-unit prices (reserve-atom
 *   ratios, NOT decimal-adjusted). See `consultScaled` for 1e18-scaled prices.
 */
contract Oracle {
    uint256 public constant MAX_OBSERVATIONS = 1024;
    uint256 public constant MIN_OBSERVATION_INTERVAL = 5 minutes;
    uint256 public constant MAX_OBSERVATION_AGE = 1 hours;
    uint256 public constant MIN_TWAP_PERIOD = 15 minutes;
    uint256 public constant MAX_TWAP_PERIOD = (MAX_OBSERVATIONS - 1) * MIN_OBSERVATION_INTERVAL;

    struct Observation {
        uint256 timestamp;
        uint256 price0Cumulative;
        uint256 price1Cumulative;
    }

    struct ObservationState {
        Observation[MAX_OBSERVATIONS] data;
        uint16 head; // next write index
        uint16 count; // min(total written, MAX_OBSERVATIONS)
    }

    address public immutable factory;

    mapping(address => ObservationState) private _observations;

    event ObservationRecorded(
        address indexed pair, uint256 timestamp, uint256 price0Cumulative, uint256 price1Cumulative
    );

    constructor(address _factory) {
        factory = _factory;
    }

    /**
     * @notice Record a new price observation for a pair.
     * @dev Permissionless but rate-limited: at most one observation per
     * MIN_OBSERVATION_INTERVAL. Overwrites the oldest entry when full.
     */
    function update(address pair) external {
        _validatePair(pair);
        (uint256 price0Cumulative, uint256 price1Cumulative, uint32 blockTimestamp) =
            _currentCumulativePrices(pair);

        ObservationState storage s = _observations[pair];
        if (s.count > 0) {
            Observation storage last = _at(s, s.count - 1);
            if (blockTimestamp < last.timestamp + MIN_OBSERVATION_INTERVAL) {
                return;
            }
        }

        s.data[s.head] = Observation({
            timestamp: blockTimestamp,
            price0Cumulative: price0Cumulative,
            price1Cumulative: price1Cumulative
        });
        s.head = uint16((uint256(s.head) + 1) % MAX_OBSERVATIONS);
        if (s.count < MAX_OBSERVATIONS) s.count++;

        emit ObservationRecorded(pair, blockTimestamp, price0Cumulative, price1Cumulative);
    }

    /// @notice Record observations for several pairs (keeper helper).
    /// @dev All-or-nothing: one invalid pair reverts the whole batch.
    function updateMany(address[] calldata pairs) external {
        for (uint256 i = 0; i < pairs.length; i++) {
            this.update(pairs[i]);
        }
    }

    /**
     * @notice Get the TWAP for token0 in terms of token1.
     * @return price0Average Average price of token0 in token1 (Q112.112, raw units).
     */
    function consult(address pair, uint256 period) external view returns (uint256 price0Average) {
        (price0Average,) = _twap(pair, period);
    }

    /**
     * @notice Get both TWAP prices.
     * @return price0Average Price of token0 in token1 (Q112.112, raw units).
     * @return price1Average Price of token1 in token0 (Q112.112, raw units).
     */
    function consultBoth(address pair, uint256 period)
        external
        view
        returns (uint256 price0Average, uint256 price1Average)
    {
        return _twap(pair, period);
    }

    /**
     * @notice Get the TWAP for token0 in token1, scaled to 1e18.
     * @dev Assumes 18-decimal tokens; use `consultScaledDecimals` otherwise.
     * Q112.112 -> 1e18: (twap * 1e18) >> 112.
     */
    function consultScaled(address pair, uint256 period)
        external
        view
        returns (uint256 price0Average)
    {
        (uint256 raw,) = _twap(pair, period);
        return _to1e18(raw);
    }

    /**
     * @notice Get the TWAP of `base` in `quote`, scaled to 1e18, adjusted for
     * token decimals (e.g. USDC(6)/WETH(18)).
     * @return price 1e18-fixed-point quote units per 1 whole base unit.
     */
    function consultScaledDecimals(address pair, address base, address quote, uint256 period)
        external
        view
        returns (uint256 price)
    {
        (address token0, address token1) = _validatePairTokens(pair);
        require(
            (base == token0 && quote == token1) || (base == token1 && quote == token0),
            "Oracle: NOT_PAIR_TOKENS"
        );
        (uint256 p0, uint256 p1) = _twap(pair, period);
        uint256 raw = base == token0 ? p0 : p1;
        uint8 baseDec = _decimalsOr18(base);
        uint8 quoteDec = _decimalsOr18(quote);
        require(quoteDec <= 18 + baseDec, "Oracle: DECIMAL_RANGE");
        return (raw * (10 ** (uint256(18) + baseDec - quoteDec))) >> 112;
    }

    /**
     * @notice Get the current spot price. NEVER use as an oracle: it is
     * manipulable within a block (swap, donation + sync). For manipulation
     * resistance use `consult` / `consultScaled` over a sufficient period.
     * @return price0Spot Current price of token0 in token1 (1e18-scaled).
     */
    function getSpotPriceUnsafe(address pair) external view returns (uint256 price0Spot) {
        _validatePair(pair);
        (uint112 reserve0, uint112 reserve1,) = Pair(pair).getReserves();
        require(reserve0 > 0 && reserve1 > 0, "Oracle: NO_RESERVES");
        price0Spot = (uint256(reserve1) * 1e18) / uint256(reserve0);
    }

    /**
     * @notice Check if price has deviated significantly from TWAP.
     * @dev FAIL-CLOSED: insufficient/stale history, invalid parameters, an
     * untrusted pair, a zero TWAP, or any internal revert all return true.
     * @return isManipulated True unless the market provably tracks its TWAP.
     */
    function isPriceManipulated(address pair, uint256 period, uint256 maxDeviation)
        external
        view
        returns (bool isManipulated)
    {
        if (period < MIN_TWAP_PERIOD || period > MAX_TWAP_PERIOD || maxDeviation > 10000) {
            return true;
        }
        try this.manipulationCheck(pair, period, maxDeviation) returns (bool m) {
            return m;
        } catch {
            return true;
        }
    }

    /// @notice Fail-closed check body; exposed for try/catch, not integrator API.
    function manipulationCheck(address pair, uint256 period, uint256 maxDeviation)
        external
        view
        returns (bool isManipulated)
    {
        _validatePair(pair);
        (uint112 reserve0, uint112 reserve1,) = Pair(pair).getReserves();
        if (reserve0 == 0 || reserve1 == 0) return true;

        (uint256 twapQ112,) = _twap(pair, period);
        uint256 twap = _to1e18(twapQ112);
        if (twap == 0) return true;

        uint256 spotPrice = (uint256(reserve1) * 1e18) / uint256(reserve0);
        uint256 deviation;
        if (spotPrice > twap) {
            deviation = ((spotPrice - twap) * 10000) / twap;
        } else {
            deviation = ((twap - spotPrice) * 10000) / twap;
        }
        isManipulated = deviation > maxDeviation;
    }

    /**
     * @notice Whether `consult(pair, period)` would succeed right now.
     * Integrators use this to distinguish "not ready" from "manipulated".
     */
    function isReady(address pair, uint256 period) external view returns (bool ready) {
        try this.consult(pair, period) returns (uint256) {
            return true;
        } catch {
            return false;
        }
    }

    /// @notice Number of stored observations for a pair (capped at MAX_OBSERVATIONS).
    function observationCount(address pair) external view returns (uint256 count) {
        return _observations[pair].count;
    }

    /// @notice Get the i-th oldest observation (0 = oldest).
    function getObservation(address pair, uint256 i)
        external
        view
        returns (Observation memory obs)
    {
        ObservationState storage s = _observations[pair];
        require(i < s.count, "Oracle: INDEX_OUT_OF_RANGE");
        return _at(s, uint16(i));
    }

    /// @notice Get latest observation for a pair.
    function latestObservation(address pair) external view returns (Observation memory obs) {
        ObservationState storage s = _observations[pair];
        require(s.count > 0, "Oracle: NO_OBSERVATIONS");
        return _at(s, s.count - 1);
    }

    // **** INTERNAL ****

    /// @dev Logical index i (0 = oldest) -> ring slot.
    function _at(ObservationState storage s, uint16 i) private view returns (Observation storage) {
        uint256 physical = (uint256(s.head) + MAX_OBSERVATIONS - s.count + i) % MAX_OBSERVATIONS;
        return s.data[physical];
    }

    /// @dev Binary search for the latest observation at or before target.
    function _findAtOrBefore(ObservationState storage s, uint256 target)
        private
        view
        returns (uint16 idx, bool found)
    {
        if (s.count == 0) return (0, false);
        if (_at(s, 0).timestamp > target) return (0, false);
        uint16 lo = 0;
        uint16 hi = s.count - 1;
        while (lo < hi) {
            uint16 mid = (lo + hi + 1) / 2;
            if (_at(s, mid).timestamp <= target) lo = mid;
            else hi = mid - 1;
        }
        return (lo, true);
    }

    /// @dev Shared TWAP lookup: freshness + full-window validation.
    function _twap(address pair, uint256 period) private view returns (uint256 p0, uint256 p1) {
        if (period < MIN_TWAP_PERIOD) revert("Oracle: PERIOD_TOO_SHORT");
        if (period > MAX_TWAP_PERIOD) revert("Oracle: PERIOD_TOO_LONG");
        _validatePair(pair);

        ObservationState storage s = _observations[pair];
        if (s.count < 2) revert("Oracle: INSUFFICIENT_OBSERVATIONS");

        Observation storage latest = _at(s, s.count - 1);
        if (block.timestamp > latest.timestamp + MAX_OBSERVATION_AGE) {
            revert("Oracle: STALE_OBSERVATION");
        }
        // Also guards `latest.timestamp - period` against underflow.
        if (period > latest.timestamp) {
            revert("Oracle: INSUFFICIENT_HISTORY");
        }

        (uint16 idx, bool found) = _findAtOrBefore(s, latest.timestamp - period);
        if (!found) revert("Oracle: INSUFFICIENT_HISTORY");
        Observation storage anchor = _at(s, idx);
        uint256 elapsed = latest.timestamp - anchor.timestamp;
        if (elapsed < period) revert("Oracle: INSUFFICIENT_HISTORY");

        unchecked {
            p0 = (latest.price0Cumulative - anchor.price0Cumulative) / elapsed;
            p1 = (latest.price1Cumulative - anchor.price1Cumulative) / elapsed;
        }
    }

    /// @dev Q112.112 raw-unit price -> 1e18 fixed point.
    function _to1e18(uint256 q112) private pure returns (uint256) {
        return (q112 * 1e18) >> 112;
    }

    function _decimalsOr18(address token) private view returns (uint8 dec) {
        dec = 18;
        if (token.code.length == 0) return dec;
        (bool ok, bytes memory ret) = token.staticcall(abi.encodeWithSignature("decimals()"));
        if (ok && ret.length == 32) {
            dec = abi.decode(ret, (uint8));
        }
    }

    /// @dev Returns (token0, token1); reverts UNTRUSTED_PAIR unless the pair
    /// was created by the known factory for exactly these tokens.
    function _validatePairTokens(address pair)
        private
        view
        returns (address token0, address token1)
    {
        if (pair.code.length == 0) {
            revert("Oracle: UNTRUSTED_PAIR");
        }
        (bool ok0, bytes memory ret0) = pair.staticcall(abi.encodeWithSignature("token0()"));
        (bool ok1, bytes memory ret1) = pair.staticcall(abi.encodeWithSignature("token1()"));
        if (!ok0 || !ok1 || ret0.length != 32 || ret1.length != 32) {
            revert("Oracle: UNTRUSTED_PAIR");
        }
        token0 = abi.decode(ret0, (address));
        token1 = abi.decode(ret1, (address));
        if (token0 == address(0) || token1 == address(0)) {
            revert("Oracle: UNTRUSTED_PAIR");
        }
        (bool okP, bytes memory retP) = factory.staticcall(
            abi.encodeWithSignature("getPair(address,address)", token0, token1)
        );
        if (!okP || retP.length != 32) revert("Oracle: UNTRUSTED_PAIR");
        if (abi.decode(retP, (address)) != pair) {
            revert("Oracle: UNTRUSTED_PAIR");
        }
    }

    function _validatePair(address pair) private view {
        _validatePairTokens(pair);
    }

    /// @dev Helper to get current cumulative prices from pair.
    function _currentCumulativePrices(address pair)
        internal
        view
        returns (uint256 price0Cumulative, uint256 price1Cumulative, uint32 blockTimestamp)
    {
        blockTimestamp = uint32(block.timestamp);
        (uint112 reserve0, uint112 reserve1, uint32 timestampLast) = Pair(pair).getReserves();

        price0Cumulative = Pair(pair).price0CumulativeLast();
        price1Cumulative = Pair(pair).price1CumulativeLast();

        // If time has elapsed since the last update on the pair,
        // accumulate the price since then.
        if (timestampLast != blockTimestamp && reserve0 > 0 && reserve1 > 0) {
            uint32 timeElapsed = blockTimestamp - timestampLast;
            unchecked {
                uint256 price0 = (uint256(reserve1) << 112) / reserve0;
                uint256 price1 = (uint256(reserve0) << 112) / reserve1;

                price0Cumulative += price0 * timeElapsed;
                price1Cumulative += price1 * timeElapsed;
            }
        }
    }
}
