// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';
import './libraries/OracleLibrary.sol';
import './libraries/TickMath.sol';

/// @title PriceOracle
/// @notice Uniswap V3 TWAP wrapper for DRB/WETH price reads on Base.
///         Reads time-weighted average prices at configurable windows (ROUND_TWAP = 5 min,
///         ANCHOR_TWAP = 30 min) and exposes a spot price derived from the pool's current tick.
///         All prices are returned as 18-decimal fixed-point values (priceX18) representing
///         the amount of quoteToken per one unit of baseToken (scaled by baseAmount).
contract PriceOracle {
    // ─── Errors ────────────────────────────────────────────────────────────────

    /// @notice Pool observation history is shorter than the requested TWAP window.
    /// @param needed Seconds requested.
    /// @param oldest Oldest observation available (seconds).
    error InsufficientCardinality(uint32 needed, uint32 oldest);

    /// @notice Spot price read attempted on an uninitialized pool (sqrtPriceX96 == 0).
    error PoolNotInitialized();

    /// @notice The computed price fell outside the sanity bounds [MIN_PRICE, MAX_PRICE].
    /// @param price The out-of-range value that was rejected.
    error PriceOutOfRange(uint256 price);

    // ─── Constants ─────────────────────────────────────────────────────────────

    /// @notice Primary TWAP window used for round settlement prices (5 minutes).
    uint32 public constant ROUND_TWAP = 300;

    /// @notice Anchor TWAP window used for deviation checks (30 minutes).
    uint32 public constant ANCHOR_TWAP = 1800;

    /// @notice Minimum accepted price (1 wei — rejects exact zero from degenerate pools).
    uint256 public constant MIN_PRICE = 1;

    /// @notice Maximum accepted price (Uniswap tick math tops out near 4.3e27 for 1e18 base; 1e30 is a tight, safe ceiling).
    uint256 public constant MAX_PRICE = 1e30;

    // ─── Functions ─────────────────────────────────────────────────────────────

    /// @notice Increase the observation cardinality of a V3 pool so TWAP history is available.
    /// @dev Idempotent — calling with a cardinality ≤ the current value is a no-op on the pool.
    /// @param pool Address of the Uniswap V3 pool.
    /// @param newCardinality Desired minimum observation cardinality.
    function warmPool(address pool, uint16 newCardinality) external {
        IUniswapV3Pool(pool).increaseObservationCardinalityNext(newCardinality);
    }

    /// @notice Read a TWAP price for a given window.
    /// @dev Reverts with InsufficientCardinality if the pool lacks enough history.
    ///      Reverts with PriceOutOfRange if the result is outside [MIN_PRICE, MAX_PRICE].
    /// @param pool     Address of the Uniswap V3 pool.
    /// @param baseToken  Token whose price is being quoted (numerator token in the ratio).
    /// @param quoteToken Token in which the price is expressed.
    /// @param baseAmount Amount of baseToken to convert (typically 1e18 for 18-decimal tokens).
    /// @param secondsAgo Length of the TWAP window in seconds.
    /// @return priceX18 Amount of quoteToken received for baseAmount of baseToken (18-decimal scaled).
    function getPriceTWAP(
        address pool,
        address baseToken,
        address quoteToken,
        uint128 baseAmount,
        uint32 secondsAgo
    ) external view returns (uint256 priceX18) {
        uint32 oldest = OracleLibrary.getOldestObservationSecondsAgo(pool);
        if (oldest < secondsAgo) revert InsufficientCardinality(secondsAgo, oldest);

        (int24 tick, ) = OracleLibrary.consult(pool, secondsAgo);
        priceX18 = OracleLibrary.getQuoteAtTick(tick, baseAmount, baseToken, quoteToken);

        if (priceX18 < MIN_PRICE || priceX18 > MAX_PRICE) revert PriceOutOfRange(priceX18);
    }

    /// @notice Read the current spot price from the pool's slot0 tick.
    /// @dev Display-only — spot price is manipulable; use getPriceTWAP for settlement.
    ///      Reverts with PoolNotInitialized if sqrtPriceX96 == 0.
    ///      Reverts with PriceOutOfRange if the result is outside [MIN_PRICE, MAX_PRICE].
    /// @param pool     Address of the Uniswap V3 pool.
    /// @param baseToken  Token whose price is being quoted.
    /// @param quoteToken Token in which the price is expressed.
    /// @param baseAmount Amount of baseToken to convert.
    /// @return priceX18 Amount of quoteToken received for baseAmount of baseToken.
    function getPriceSpot(
        address pool,
        address baseToken,
        address quoteToken,
        uint128 baseAmount
    ) external view returns (uint256 priceX18) {
        (uint160 sqrtPriceX96, int24 tick, , , , , ) = IUniswapV3Pool(pool).slot0();
        if (sqrtPriceX96 == 0) revert PoolNotInitialized();

        priceX18 = OracleLibrary.getQuoteAtTick(tick, baseAmount, baseToken, quoteToken);

        if (priceX18 < MIN_PRICE || priceX18 > MAX_PRICE) revert PriceOutOfRange(priceX18);
    }

    /// @notice Compute the 5-minute TWAP and validate it against the 30-minute anchor.
    /// @dev Returns ok=false (rather than reverting) if anchor history is unavailable or if
    ///      the deviation exceeds maxDevBps, so callers can choose how to handle stale/volatile prices.
    /// @param pool       Address of the Uniswap V3 pool.
    /// @param baseToken  Token whose price is being quoted.
    /// @param quoteToken Token in which the price is expressed.
    /// @param baseAmount Amount of baseToken to convert.
    /// @param maxDevBps  Maximum acceptable deviation between ROUND_TWAP and ANCHOR_TWAP in basis points.
    /// @return p  The ROUND_TWAP price (amount of quoteToken for baseAmount of baseToken).
    /// @return ok True when anchor history exists and the deviation is within maxDevBps.
    function getRoundPrice(
        address pool,
        address baseToken,
        address quoteToken,
        uint128 baseAmount,
        uint256 maxDevBps
    ) external view returns (uint256 p, bool ok) {
        uint32 oldest = OracleLibrary.getOldestObservationSecondsAgo(pool);
        if (oldest < ROUND_TWAP) revert InsufficientCardinality(ROUND_TWAP, oldest);

        (int24 tick, ) = OracleLibrary.consult(pool, ROUND_TWAP);
        p = OracleLibrary.getQuoteAtTick(tick, baseAmount, baseToken, quoteToken);
        if (p < MIN_PRICE || p > MAX_PRICE) revert PriceOutOfRange(p);

        if (oldest < ANCHOR_TWAP) {
            ok = false;
            return (p, ok);
        }

        (int24 anchorTick, ) = OracleLibrary.consult(pool, ANCHOR_TWAP);
        uint256 anchor = OracleLibrary.getQuoteAtTick(anchorTick, baseAmount, baseToken, quoteToken);
        if (anchor < MIN_PRICE || anchor > MAX_PRICE) revert PriceOutOfRange(anchor);

        uint256 deviation = p > anchor ? p - anchor : anchor - p;
        ok = (deviation * 10_000 <= anchor * maxDevBps);
    }

    /// @notice Return the harmonic mean liquidity for a pool over a given window.
    /// @param pool       Address of the Uniswap V3 pool.
    /// @param secondsAgo Length of the observation window in seconds.
    /// @return liq The harmonic mean in-range liquidity over the window.
    function getHarmonicMeanLiquidity(address pool, uint32 secondsAgo)
        external
        view
        returns (uint128 liq)
    {
        (, liq) = OracleLibrary.consult(pool, secondsAgo);
    }
}
