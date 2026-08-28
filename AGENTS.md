# Agent Instructions

Tools:

- `task` as task runner
- `mise` pins every dev tool (see `.mise.toml` / `mise.lock`)

See [`CONTRIBUTING.md`](CONTRIBUTING.md) for tooling and code conventions,
and [`SPEC.md`](SPEC.md) / [`README.md`](README.md) for what this
repository is and how it's laid out.

## Commits

Commit proactively, without waiting to be asked, once a clearly delineated
and scoped piece of work is done and validates cleanly (`task validate`
passing is the bar). A plan's phase completing, a self-contained unit of
work landing, or a specific delineated request from the user being fully
carried out, all count. When the user is giving a run of ad hoc
instructions with no larger plan behind them, don't treat each individual
instruction as its own commit boundary by default - wait for a point that
represents a coherent, reviewable change.

Do not ask for permission before committing at one of these points - just
commit. Asking defeats the point of "proactively, without waiting to be
asked". If something about the commit itself is genuinely in question (e.g.
whether to include a file), resolve that directly rather than turning it
into a yes/no confirmation prompt.
