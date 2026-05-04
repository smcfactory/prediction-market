# v3-oracle — vendored, 0.8.x-patched

Operator-managed vendoring of the three Uniswap V3 oracle math libraries needed by `PriceOracle.sol` (per Issue #18). Distinct from `lib/v3-core/` and `lib/v3-periphery/` which are upstream pristine submodules pinned to v1.0.0 / v1.3.0 respectively.

These files have been **patched for solc 0.8.26 compatibility** and are NOT a drop-in replacement for the upstream code. The patches are documented inline in each file's header.

## Files

| File | Source | License | Patches |
|---|---|---|---|
| `FullMath.sol` | `@uniswap/v3-core` v1.0.0 ([source](https://github.com/Uniswap/v3-core/blob/v1.0.0/contracts/libraries/FullMath.sol)) | MIT | Overflow-prone arithmetic wrapped in `unchecked {}` blocks |
| `OracleLibrary.sol` | `@uniswap/v3-periphery` v1.3.0 ([source](https://github.com/Uniswap/v3-periphery/blob/v1.3.0/contracts/libraries/OracleLibrary.sol)) | GPL-2.0-or-later | Pragma widened from `>=0.5.0 <0.8.0` to `>=0.5.0`; mixed-arithmetic fix `int56(uint56(...))` |
| `TickMath.sol` | `@uniswap/v3-core` v1.0.0 ([source](https://github.com/Uniswap/v3-core/blob/v1.0.0/contracts/libraries/TickMath.sol)) | GPL-2.0-or-later | `uint256(MAX_TICK)` → `uint256(uint24(MAX_TICK))` (Solidity 0.8 enforces explicit narrowing/widening) |

Original license headers preserved on each file. Patch notes inline in each file's top-of-file comment.

## How to use

From any contract under `projects/drb/contracts/`:

```solidity
import { TickMath } from "../lib/v3-oracle/TickMath.sol";
import { OracleLibrary } from "../lib/v3-oracle/OracleLibrary.sol";
import { FullMath } from "../lib/v3-oracle/FullMath.sol";
```

(Relative imports — Foundry resolves these without remapping changes.)

## Why a separate dir from the v3-core / v3-periphery submodules

The submodules are PRISTINE upstream code held for reference. They cannot compile under solc 0.8.x without modification. We pin them to specific commits for reproducibility and audit but do not import from them directly.

The patched copies in this directory are what `projects/drb/contracts/` actually depends on. They are operator-managed (per Issue #18 prerequisite + `.gan/policies/forbidden-paths.json` includes `projects/drb/lib/**`). The GAN-loop builder cannot edit these files; if it needs a new vendored library, it requests it via the research back-channel.

## Provenance

This directory was added 2026-05-04 by operator (admin-bypass merge, branch `vendor/v3-oracle-libs`) as a prerequisite for unblocking Issue #18. The patches were originally produced inside PR #15 (`task/14-feat-drb-priceoracle-sol-tests-re-attemp`) which was closed as superseded.
