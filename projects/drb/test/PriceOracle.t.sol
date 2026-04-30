// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../contracts/PriceOracle.sol";

/// @dev Minimal mock that satisfies the IUniswapV3Pool selectors called by OracleLibrary.
///      Simulates a pool with a constant tick across all TWAP windows and a fixed observation age.
contract MockV3Pool {
    int24 public immutable mockTick;
    uint32 public immutable oldestAge;

    constructor(int24 _mockTick, uint32 _oldestAge) {
        mockTick = _mockTick;
        oldestAge = _oldestAge;
    }

    /// @dev Returns cardinality=1 so getOldestObservationSecondsAgo reads observations(0).
    ///      sqrtPriceX96=1 signals an initialized pool; tick reflects mockTick for getPriceSpot.
    function slot0()
        external
        view
        returns (uint160, int24, uint16, uint16, uint16, uint8, bool)
    {
        return (uint160(1), mockTick, uint16(0), uint16(1), uint16(1), uint8(0), true);
    }

    /// @dev observations(0) holds the oldest (and only) entry, timestamped `oldestAge` seconds ago.
    function observations(uint256)
        external
        view
        returns (uint32, int56, uint160, bool)
    {
        return (uint32(block.timestamp) - oldestAge, int56(0), uint160(0), true);
    }

    /// @dev Returns tick cumulatives that give arithmeticMeanTick == mockTick for any window.
    ///      tickCumulatives[1] - tickCumulatives[0] = mockTick * secondsAgos[0].
    function observe(uint32[] calldata secondsAgos)
        external
        view
        returns (int56[] memory tickCumulatives, uint160[] memory secPerLiq)
    {
        tickCumulatives = new int56[](2);
        secPerLiq = new uint160[](2);
        uint32 duration = secondsAgos[0];
        // tick * duration = tickCumulatives[1] - tickCumulatives[0]
        // Set tickCumulatives[1]=0, tickCumulatives[0] = -mockTick * duration
        tickCumulatives[0] = -int56(mockTick) * int56(uint56(duration));
        tickCumulatives[1] = 0;
        secPerLiq[0] = 0;
        secPerLiq[1] = 1e30;
    }

    function increaseObservationCardinalityNext(uint16) external {}
}

contract PriceOracleTest is Test {
    /// @dev Pinned Base mainnet block for deterministic fork tests (~Aug 2025).
    ///      Pool deployed ~block 27.5M; cardinality raised to 10000 before block 30M,
    ///      giving ≥20 000 s of TWAP history (well above ANCHOR_TWAP=1800 s).
    uint256 constant FORK_BLOCK = 30_000_000;

    address constant DRB  = 0x3ec2156D4c0A9CBdAB4a016633b7BcF6a8d68Ea2;
    address constant POOL = 0x5116773e18A9C7bB03EBB961b38678E45E238923; // DRB/WETH 1%
    address constant WETH = 0x4200000000000000000000000000000000000006;

    uint32  constant ROUND_TWAP  = 300;
    uint32  constant ANCHOR_TWAP = 1800;
    uint256 constant MAX_PRICE   = type(uint256).max / 1e18;

    PriceOracle oracle;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("base"), FORK_BLOCK);
        oracle = new PriceOracle();
    }

    // ─── Real-pool fork tests ──────────────────────────────────────────────────

    function test_warmPool_idempotent() public {
        uint16 cardinality = 50;
        oracle.warmPool(POOL, cardinality);
        oracle.warmPool(POOL, cardinality); // idempotent — must not revert
    }

    function test_getPriceSpot_drb_weth() public {
        uint256 spot = oracle.getPriceSpot(POOL, DRB, WETH, 1 ether);
        assertGt(spot, 0, "spot price must be non-zero");
        assertLt(spot, MAX_PRICE, "spot price must be below MAX_PRICE");
    }

    function test_getPriceTWAP_300s_drb_weth() public {
        uint256 spot = oracle.getPriceSpot(POOL, DRB, WETH, 1 ether);
        uint256 twap = oracle.getPriceTWAP(POOL, DRB, WETH, 1 ether, ROUND_TWAP);

        assertGt(twap, 0, "TWAP must be non-zero");
        assertLt(twap, MAX_PRICE, "TWAP must be below MAX_PRICE");
        // TWAP and spot should be within 2x of each other (sanity — not a tight bound)
        assertGt(twap, spot / 2, "TWAP should be within 2x below spot");
        assertLt(twap, spot * 2, "TWAP should be within 2x above spot");
    }

    function test_getRoundPrice_returnsPrimaryAndAnchor_okTrue() public {
        // With 100% tolerance every deviation passes → ok must be true
        (uint256 p, bool ok) = oracle.getRoundPrice(POOL, DRB, WETH, 1 ether, 10_000);
        assertGt(p, 0, "round price must be non-zero");
        assertLt(p, MAX_PRICE, "round price must be below MAX_PRICE");
        assertTrue(ok, "should be ok with 100% deviation tolerance");
    }

    function test_getRoundPrice_okFalse_whenAnchorDeviates() public {
        // maxDevBps=0 means any nonzero deviation between the 5-min and 30-min TWAP trips ok=false.
        // The real DRB/WETH pool at block 30_000_000 has a non-flat price history, so the two
        // TWAPs differ and the deviation guard fires.
        (, bool ok) = oracle.getRoundPrice(POOL, DRB, WETH, 1 ether, 0);
        assertFalse(ok, "getRoundPrice: deviation guard must trip with maxDevBps=0 on real DRB/WETH pool");
    }

    function test_getHarmonicMeanLiquidity_drb_weth() public {
        uint128 liq = oracle.getHarmonicMeanLiquidity(POOL, ROUND_TWAP);
        assertGt(liq, 0, "harmonic mean liquidity must be non-zero for active pool");
    }

    // ─── Mock-pool edge-case tests ─────────────────────────────────────────────

    function test_getPriceTWAP_reverts_insufficientCardinality() public {
        // Mock pool with only 100 s of history; requesting 1000 s must revert.
        MockV3Pool mockPool = new MockV3Pool(int24(0), uint32(100));
        vm.expectRevert(
            abi.encodeWithSelector(
                PriceOracle.InsufficientCardinality.selector,
                uint32(1000),
                uint32(100)
            )
        );
        oracle.getPriceTWAP(address(mockPool), address(1), address(2), 1, 1000);
    }

    function test_getPriceSpot_reverts_priceOutOfRange_zero() public {
        // Pool fixture at MIN_TICK (-887272): slot0 returns sqrtPriceX96=1 (initialized, non-zero)
        // with tick=MIN_TICK. getPriceSpot reads tick directly from slot0 and calls
        // getQuoteAtTick(MIN_TICK, 1, addr(1), addr(2)). With addr(1) < addr(2):
        //   mulDiv(MIN_SQRT_RATIO^2 ≈ 1.84e19, 1, 2^192) = 0 → PriceOutOfRange(0).
        MockV3Pool zeroPool = new MockV3Pool(int24(-887272), uint32(0));
        vm.expectRevert(
            abi.encodeWithSelector(PriceOracle.PriceOutOfRange.selector, uint256(0))
        );
        oracle.getPriceSpot(address(zeroPool), address(1), address(2), uint128(1));
    }
}
