# drb — DRB Prediction Market

An on-chain prediction market for **$DRB token price moves** on Base. Users take directional positions on whether the DRB token price will be higher or lower at a defined future settlement time, using the DRB/WETH 1% Uniswap V3 pool (`0x5116773e18a9c7bb03ebb961b38678e45e238923`) as the on-chain price oracle. DRB token: `0x3ec2156D4c0A9CBdAB4a016633b7BcF6a8d68Ea2` (Base, chain id 8453).

## Dependencies

| Library | Version | Purpose |
|---|---|---|
| OpenZeppelin Contracts | v5.0.2 | ERC-20, access control, safe math |
| Uniswap V3 Core | v1.0.0 | Pool interfaces and oracle TWAP |
| Uniswap V3 Periphery | v1.3.0 | Quoter and router interfaces |
| forge-std | v1.16.1 | Foundry test utilities |

## Development

```bash
# Install dependencies (first time or after cloning)
forge install

# Compile contracts
forge build

# Run tests
forge test
```

## Design brief

`~/claude-builder-state/research/market-design-brief.md` (build VPS) — locked decisions on settlement currency, resolution mechanism, and market mechanics.
