// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "./libraries/OracleLibrary.sol";
import "./libraries/TickMath.sol";

/// @title PriceOracle
/// @notice Thin Uniswap V3 TWAP wrapper for DRB/WETH price reads.
///         TWAP reads are safe for settlement; spot reads are display-only.
contract PriceOracle {
    /// @notice Pool history too short to satisfy the requested TWAP window.
    error InsufficientCardinality(uint32 needed, uint32 oldest);
    /// @notice Pool has not been initialised (sqrtPriceX96 == 0).
    error PoolNotInitialized();

    /// @notice 5-minute TWAP window used for round binding price.
    uint32 public constant ROUND_TWAP = 300;

    /// @notice 30-minute TWAP window used as anti-manipulation anchor.
    uint32 public constant ANCHOR_TWAP = 1800;

    // -----------------------------------------------------------------------
    // Warm-up
    // -----------------------------------------------------------------------

    /// @notice Increases the pool's observation cardinality buffer so that
    ///         future TWAP windows can be served without gaps.
    /// @dev    Idempotent — safe to call repeatedly with any value ≥ current.
    ///         Anyone can call; there is no access control.
    /// @param pool           Uniswap V3 pool address.
    /// @param newCardinality Desired observation cardinality.
    function warmPool(address pool, uint16 newCardinality) external {
        IUniswapV3Pool(pool).increaseObservationCardinalityNext(newCardinality);
    }

    // -----------------------------------------------------------------------
    // TWAP reads
    // -----------------------------------------------------------------------

    /// @notice Returns the time-weighted average price of baseToken denominated
    ///         in quoteToken, scaled to 1e18 base units.
    /// @dev    Uses OracleLibrary.consult for flash-loan-resistant reads.
    ///         Reverts InsufficientCardinality when the pool's oldest stored
    ///         observation is newer than secondsAgo.
    /// @param pool        Uniswap V3 pool address.
    /// @param baseToken   Token being priced.
    /// @param quoteToken  Denomination token.
    /// @param secondsAgo  TWAP window length in seconds (must be > 0).
    /// @return priceX18   Price of 1e18 units of baseToken in quoteToken.
    function getPriceTWAP(
        address pool,
        address baseToken,
        address quoteToken,
        uint32 secondsAgo
    ) public view returns (uint256 priceX18) {
        uint32 oldest = OracleLibrary.getOldestObservationSecondsAgo(pool);
        if (oldest < secondsAgo) revert InsufficientCardinality(secondsAgo, oldest);

        (int24 meanTick,) = OracleLibrary.consult(pool, secondsAgo);
        priceX18 = OracleLibrary.getQuoteAtTick(meanTick, uint128(1e18), baseToken, quoteToken);
    }

    // -----------------------------------------------------------------------
    // Spot read (display-only)
    // -----------------------------------------------------------------------

    /// @notice Returns the current spot price from slot0.
    /// @dev    DISPLAY-ONLY — NEVER use for settlement. slot0 sqrtPriceX96 is
    ///         single-block flash-loan manipulable. Reverts PoolNotInitialized
    ///         when the pool has not been seeded.
    /// @param pool        Uniswap V3 pool address.
    /// @param baseToken   Token being priced.
    /// @param quoteToken  Denomination token.
    /// @return priceX18   Spot price of 1e18 units of baseToken in quoteToken.
    function getPriceSpot(
        address pool,
        address baseToken,
        address quoteToken
    ) external view returns (uint256 priceX18) {
        (uint160 sqrtPriceX96,,,,,, ) = IUniswapV3Pool(pool).slot0();
        if (sqrtPriceX96 == 0) revert PoolNotInitialized();
        int24 tick = TickMath.getTickAtSqrtRatio(sqrtPriceX96);
        priceX18 = OracleLibrary.getQuoteAtTick(tick, uint128(1e18), baseToken, quoteToken);
    }

    // -----------------------------------------------------------------------
    // Round price + manipulation guard
    // -----------------------------------------------------------------------

    /// @notice Returns the 5-min TWAP and a boolean manipulation-safety flag.
    /// @dev    `ok` is false when the 30-min anchor TWAP deviates from the
    ///         5-min price by more than maxDevBps basis points. The market
    ///         contract uses ok==false to trigger round cancellation.
    /// @param pool        Uniswap V3 pool address.
    /// @param baseToken   Token being priced.
    /// @param quoteToken  Denomination token.
    /// @param maxDevBps   Maximum allowed deviation in basis points (e.g. 200 = 2 %).
    /// @return p          5-minute TWAP (1e18-scaled).
    /// @return ok         True iff the 30-min anchor is within maxDevBps of p.
    function getRoundPrice(
        address pool,
        address baseToken,
        address quoteToken,
        uint16 maxDevBps
    ) external view returns (uint256 p, bool ok) {
        p = getPriceTWAP(pool, baseToken, quoteToken, ROUND_TWAP);
        uint256 anchor = getPriceTWAP(pool, baseToken, quoteToken, ANCHOR_TWAP);
        uint256 diff = p > anchor ? p - anchor : anchor - p;
        ok = diff * 10_000 <= anchor * maxDevBps;
    }

    // -----------------------------------------------------------------------
    // Liquidity read
    // -----------------------------------------------------------------------

    /// @notice Returns the harmonic mean liquidity over the requested window.
    /// @dev    Used by the market contract as a liquidity guardrail before
    ///         accepting a new round. Delegates directly to OracleLibrary.consult.
    /// @param pool        Uniswap V3 pool address.
    /// @param secondsAgo  Observation window in seconds (must be > 0).
    /// @return liq        Harmonic mean in-range liquidity.
    function getHarmonicMeanLiquidity(
        address pool,
        uint32 secondsAgo
    ) external view returns (uint128 liq) {
        (, liq) = OracleLibrary.consult(pool, secondsAgo);
    }
}
