# Prediction Market

The DRB Prediction Market. Built **for agents, not humans** — and built **by agents**, in public.

The contracts in this repo are written, reviewed, and merged by an autonomous Claude+Codex loop. A human (the operator, [@vasilichnick](https://github.com/vasilichnick)) only steps in on `task:escalated`. Everything else — building, reviewing, merging — happens between two AI agents talking through GitHub.

## What we're building

An on-chain prediction market for **$DRB token price moves** on Base. Protocol details — settlement currency, resolution mechanism, market mechanics — are in active research and not yet finalized. The synthesized brief lands at `projects/drb/brief.md` once research is complete; from there the build proceeds task by task through the GAN loop described below.

## How it gets built — the GAN loop

```
    [Operator opens issue + writes brief]
                  │
                  ▼
            task:ready-code
                  │
                  ▼
   ┌──────────────────────────────┐
   │  Builder agent (Claude Code) │
   │  • reads issue + brief       │
   │  • writes code in a branch   │
   │  • opens PR                  │
   └─────────────┬────────────────┘
                 │
                 ▼
            task:ready-review
                 │
                 ▼
   ┌──────────────────────────────┐
   │  Reviewer agent (Codex CLI)  │
   │  • reads PR + runs tests     │
   │  • approves or requests      │
   │    changes                   │
   └─────────────┬────────────────┘
                 │
       ┌─────────┴─────────┐
       ▼                   ▼
  task:approved   task:changes-requested
       │                   │ (round counter +1, back to builder)
       ▼                   │
  Builder squash-merges    │ (round=3 → task:escalated → operator pinged)
       │                   │
       ▼                   ▼
  task:merged          [operator decision]
```

GitHub is the entire message bus. Issues, PRs, labels, reviews. No custom orchestration; no hidden coordination layer.

## How to follow along

- **Issues** — open issues with `task:*` labels show what's in flight. The label tells you the state.
- **PRs** — every PR is a real iteration. The conversation between builder and reviewer is public.
- **Commits on `main`** — the linear history of merged tasks is the project's actual progress.
- **Briefs** — `projects/drb/brief.md` is the spec each task is built against.
- **Research** — `projects/drb/research/` holds the source material the brief was synthesized from.

## State machine

Every issue moves through these labels in order:

| Label | Meaning |
|---|---|
| `task:ready-code` | Issue ready, builder claims on next cycle |
| `task:in-progress` | Builder writing |
| `task:ready-review` | PR open, reviewer claims on next cycle |
| `task:reviewing` | Reviewer reading the PR |
| `task:approved` | Reviewer signed off, builder merges |
| `task:changes-requested` | Reviewer rejected; builder iterates |
| `task:merging` | Squash merge in flight |
| `task:merged` | Done; main updated, branch deleted |
| `task:merge-failed` | Auto-merge refused (CI red, conflict, ruleset block) |
| `task:escalated` | 3 rounds didn't converge — operator pulled in |
| `round:1`, `round:2`, `round:3` | Iteration counter on `task:reviewing` |

## Bots and humans

| Identity | Type | Role |
|---|---|---|
| `builder-bot` | GitHub App: `smcfactory-claude-builder` | Writes code, opens PRs, merges |
| `reviewer-bot` | GitHub App: `smcfactory-codex-reviewer` | Reviews PRs, approves or requests changes |
| `@smcfactory/founders` | GitHub team (humans) | Approves changes to `.github/workflows/**` and `CODEOWNERS`; receives escalations |

`CODEOWNERS` prevents either bot from modifying its own pipeline. Bots can't escalate themselves; only the founders team can change the rules of the game.

## Current status

**Infrastructure: ready.** Apps, ruleset, CODEOWNERS, label state machine all live.

**Runtime: not yet wired.** The webhook listeners on the two VPS that host the bots are scoped but not deployed. The first end-to-end task is the proof the pipeline works — that task closes itself by merging this layout into `main`.

When the first task closes (`task:merged`), this section will be updated with the link.

## Layout

```
prediction-market/
├── README.md                  # this file
├── projects/
│   └── drb/
│       ├── README.md
│       ├── brief.md           # synthesized task spec the bots read
│       └── research/          # source material the brief was synthesized from
│           ├── claude.md
│           └── chatgpt.md
├── docs/                      # cross-product engine docs (state-machine rationale, etc.)
└── .github/
    ├── CODEOWNERS
    └── workflows/
        └── ci.yml
```

The `projects/drb/` directory will grow with build artifacts (contracts, tests, deployment scripts) as tasks land. Final layout depends on the architectural decisions the research surfaces.

## Why this exists

Two things at once:

1. **A real product.** The DRB Prediction Market is not a toy. The DRB token is live on Base. Whatever ships from this repo is the real thing.
2. **A demonstration.** Watching agents build a real product — branch by branch, review by review, merge by merge — is the whole point. The repo is the dataset.

If something here looks rough, that's because the agents are figuring it out. The history of `main` is the record.

