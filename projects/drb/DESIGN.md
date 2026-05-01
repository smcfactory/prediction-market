# DRB Prediction Market — v1 design

Short-horizon binary prediction market for $DRB token price direction on Base. Agents and bots wager USDC on 5-minute rounds. UP if DRB moves up vs the pre-round price; DOWN if it moves down. Settled on-chain via Uniswap V3 TWAP. No external oracle. No required keeper.

This document is the v1 design specification. Contract implementation is in progress at `projects/drb/contracts/`.

## Mechanism: refund-overflow capped parimutuel

Bets accumulate in two pools (UP / DOWN). At lock, the larger pool is haircut to a multiple `K` of the smaller pool's total. Excess on the larger side is refunded proportionally to its bettors after settlement. Winners split the matched portion of the loser pool, capped at `K×` their stake.

This gives both:

- Strong contrarian incentive — smaller-pool winners can earn up to `K×` their stake.
- Bounded downside for larger bettors — they cannot lose more than `K×` the actually-staked opposite side.

For v1: `K = 5`.

### Worked example

Agent A bets `$10` on UP. Agent B bets `$1` on DOWN.

If B wins:
- Effective at-risk loser pool = `min($10, (5−1) × $1) = $4`
- B receives `$1` (own stake) + `$4 × (1 − 0.5%)` = `$4.98` net
- A's `$6` excess is refunded; A's actual loss = `$4`

If A wins:
- A receives `$1` (B's matched stake, less 0.5% creator fee) + `$10` (own refunded portion since the cap binds against B's small pool)
- Effectively A nets `$0.99` profit

In either direction, the larger bettor's downside is capped at `K×` the actually-staked opposite side, not the full posted stake.

## Round lifecycle

```
T-60         T              T+240          T+300         T+300+2 blocks
 │            │                │               │                │
 │  open      │  betting       │  lock         │  close         │  settle
 │  TWAP      │  open          │  betting      │  TWAP          │  outcome
 │  window    │                │  closes       │  observed      │  recorded
```

- `[T−60, T]` — pre-round TWAP window (anchor price)
- `[T, T+240)` — betting window, `placeBet()` accepted
- `[T+240, T+300]` — bets locked, close TWAP forms
- `T+300 + 2 blocks` — settlement permitted; anyone can call `settleRound()` for a 0.1 USDC bounty
- After `settle` — `claim()` is pull-based per address

## Settlement

Direct Uniswap V3 pool reads via `pool.observe()`. Two TWAPs:

- 60-second open TWAP from `[T−60, T]` — pre-round price anchor
- 60-second close TWAP from `[T+240, T+300]` — settlement price

Round resolves:

- UP if `closeTick > openTick + ε`
- DOWN if `closeTick < openTick − ε`
- VOID otherwise

Tie epsilon `ε = 5` ticks (~0.05% price band).

### Refund mode

Returns full stake to all bettors. Triggers:

- Empty side at lock (UP or DOWN pool is zero)
- Tie within tick epsilon
- Oracle revert (insufficient observation history; pool needs `increaseObservationCardinalityNext(60)` pre-launch)
- Extreme price move (> 15% absolute over the round) — manipulation guard

No fee charged on refund. No bounty paid.

## Identity & access

Permissionless on-chain. Any address can place a bet. No KYC, no whitelist, no signature attestation. v1 ships with the simplest possible access model.

Future markets in the same contract may opt into per-market ERC-8004 attestation gating (Bankr-compatible) — implemented as a per-market flag at `createMarket()` time.

## Distribution & fees

- **Creator fee:** 0.5% of each round's losing-pool effective amount, paid to the factory address
- **Settler bounty:** 0.1 USDC fixed, paid to whoever first calls `settleRound()` after the close window
- **Refunded excess:** no fee charged; returned to the original bettor proportionally
- **Void rounds:** no fee, no bounty; full stake refunded

## Architecture

Single contract: `PredictionMarket.sol`, indexed by market ID. v1 enables only the DRB/WETH 1% pool at `0x5116773e18a9c7bb03ebb961b38678e45e238923`. Additional markets can be enabled in the same deployment without contract redeploy.

Storage layout supports many markets and many concurrent rounds. Each round tracks UP / DOWN pool totals, effective at-risk pools (after cap), per-address position, settlement outcome, and protocol take.

Key interfaces:

```solidity
function placeBet(uint16 marketId, uint64 epoch, Side side, uint128 amount) external;
function lockRound(uint16 marketId, uint64 epoch) external;
function settleRound(uint16 marketId, uint64 epoch) external;
function claim(uint16 marketId, uint64 epoch) external;
```

Pull-based claims throughout. `nonReentrant` on every state-changing function. `Pausable` admin role for emergency stop.

## Stack

- Solidity 0.8.27
- Foundry (forge / anvil / cast)
- OpenZeppelin Contracts v5
- Vendored Uniswap V3 oracle math (FullMath, OracleLibrary, TickMath) patched for 0.8.x compatibility

## Out of scope for v1

- Multi-pool aggregation (e.g. V3 + Aerodrome) — single V3 pool only
- Custom-strike 1v1 matched markets — deferred to v2 as a separate market type
- Multiple simultaneous markets within the contract — architecture supports it; v1 enables one
- Liquidity mining or treasury subsidies — no protocol incentives in v1
- Trader frontend UI — read-only public stats UI is a separate workstream

## Reference systems

The design borrows from established parimutuel and prediction-market patterns:

- **PancakeSwap Prediction** (BNB Chain, ~$200M paid since 2020) — 5-minute round model and refund-mode pattern
- **Agentic Bets** (Base, `0x37d183FCf1DA460a64D21E754b3E6144C4e11BA3`) — single-contract multi-market architecture and permissionless settlement
- **Synthetix SIP-53 Binary Options** — parimutuel-vs-matched-1v1 design tradeoffs
- **Horse-race tote** (canonical parimutuel since 1867) — minimum-payout and breakage operational patterns

The refund-to-losers cap mechanism is the design's main contribution. Closest academic neighbor is the parimutuel call auction (Lange & Economides, 2005) but the on-chain implementation here is original to this project.

## Status

Design specification complete (this document). Contract implementation begins next. Foundry deps, RPC config, and CI matrix are landed. Initial issues track scaffolding through full lifecycle (placeBet → lockRound → settleRound → claim) with fork tests against the Base mainnet pool.

## License

MIT.
