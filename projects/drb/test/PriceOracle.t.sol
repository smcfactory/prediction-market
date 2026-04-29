// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../contracts/PriceOracle.sol";

contract PriceOracleTest is Test {
    // Pinned block — Base mainnet at PR-creation time (2026-04-29 ~block 45353000).
    uint256 internal constant PINNED_BLOCK = 45_353_000;

    // DRB/WETH 1% Uniswap V3 pool on Base.
    address internal constant POOL = 0x5116773e18A9C7bB03EBB961b38678E45E238923;
    // DRB token (token0 — address sorts before WETH).
    address internal constant DRB = 0x3ec2156D4c0A9CBdAB4a016633b7BcF6a8d68Ea2;
    // Canonical WETH on Base (token1).
    address internal constant WETH = 0x4200000000000000000000000000000000000006;

    PriceOracle internal oracle;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("base"), PINNED_BLOCK);
        oracle = new PriceOracle();
    }

    // -----------------------------------------------------------------------
    // warmPool
    // -----------------------------------------------------------------------

    function test_warmPool_idempotent() public {
        // Pool already has cardinality 10_000; both calls are no-ops.
        oracle.warmPool(POOL, 300);
        oracle.warmPool(POOL, 300);
    }

    // -----------------------------------------------------------------------
    // getPriceSpot
    // -----------------------------------------------------------------------

    function test_getPriceSpot_drb_weth() public {
        uint256 price = oracle.getPriceSpot(POOL, DRB, WETH);

        assertTrue(price > 0, "spot price must be non-zero");
        // DRB is a low-price token; 1e18 DRB costs roughly 1e9–1e12 wei WETH.
        assertGt(price, 1e6, "spot price sanity lower bound");
        assertLt(price, 1e15, "spot price sanity upper bound");

        console.log("getPriceSpot DRB/WETH:", price);
    }

    // -----------------------------------------------------------------------
    // getPriceTWAP
    // -----------------------------------------------------------------------

    function test_getPriceTWAP_300s_drb_weth() public {
        uint256 twap = oracle.getPriceTWAP(POOL, DRB, WETH, 300);

        assertTrue(twap > 0, "5-min TWAP must be non-zero");
        assertGt(twap, 1e6,  "TWAP sanity lower bound");
        assertLt(twap, 1e15, "TWAP sanity upper bound");

        // TWAP should be within ±50 % of spot — loose sanity check.
        uint256 spot = oracle.getPriceSpot(POOL, DRB, WETH);
        uint256 diff = twap > spot ? twap - spot : spot - twap;
        assertLt(diff, spot / 2, "5-min TWAP vs spot deviation > 50%");

        console.log("getPriceTWAP 300s DRB/WETH:", twap);
        console.log("getPriceSpot DRB/WETH:      ", spot);
    }

    function test_getPriceTWAP_reverts_insufficientCardinality() public {
        // At PINNED_BLOCK the oldest observation is ~62 days old (~5.3 M seconds).
        // 8_000_000 s (~92 days) exceeds that window and must trigger InsufficientCardinality.
        uint32 tooOld = 8_000_000;
        // vm.expectRevert(bytes4) in Foundry v1 does full-data matching, so we use try/catch
        // to check the selector without needing the exact `oldest` argument.
        bool reverted;
        bytes4 gotSel;
        try oracle.getPriceTWAP(POOL, DRB, WETH, tooOld) {
            reverted = false;
        } catch (bytes memory reason) {
            reverted = true;
            if (reason.length >= 4) {
                bytes4 s;
                assembly { s := mload(add(reason, 32)) }
                gotSel = s;
            }
        }
        assertTrue(reverted, "expected InsufficientCardinality revert");
        assertEq(gotSel, PriceOracle.InsufficientCardinality.selector, "wrong error selector");
    }

    // -----------------------------------------------------------------------
    // getRoundPrice
    // -----------------------------------------------------------------------

    function test_getRoundPrice_returnsPrimaryAndAnchor() public {
        // 500 bps = 5 % tolerance — should pass for a healthy pool.
        (uint256 p, bool ok) = oracle.getRoundPrice(POOL, DRB, WETH, 500);

        assertTrue(p > 0, "round price must be non-zero");
        assertGt(p, 1e6,  "round price sanity lower bound");
        assertLt(p, 1e15, "round price sanity upper bound");
        assertTrue(ok, "5% tolerance should accept normal pool deviation");

        console.log("getRoundPrice p:", p, "ok:", ok ? 1 : 0);

        // Tighten to 1 bps — should reject (5-min and 30-min TWAPs differ by > 0.01 %).
        (, bool okTight) = oracle.getRoundPrice(POOL, DRB, WETH, 1);
        assertFalse(okTight, "1 bps tolerance should reject almost any pool");
    }

    function test_getRoundPrice_okFalse_whenAnchorDeviates() public {
        // maxDevBps == 0 demands 5-min TWAP == 30-min TWAP exactly, which never holds.
        (, bool ok) = oracle.getRoundPrice(POOL, DRB, WETH, 0);
        assertFalse(ok, "zero tolerance must always produce ok=false");
    }

    // -----------------------------------------------------------------------
    // getHarmonicMeanLiquidity
    // -----------------------------------------------------------------------

    function test_getHarmonicMeanLiquidity_drb_weth() public {
        uint128 liq = oracle.getHarmonicMeanLiquidity(POOL, 300);
        assertTrue(liq > 0, "harmonic mean liquidity must be non-zero for an active pool");
        console.log("harmonicMeanLiquidity 300s:", liq);
    }
}
