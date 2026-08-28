# Agent Instructions

Tools:

- `task` as task runner
- `mise` pins every dev tool (see `.mise.toml` / `mise.lock`)
- `docker compose` (`actions/renovate/docker-compose.yaml`) runs Renovate;
  the top-level `docker-compose.yaml` is unrelated devtools tooling

Other info:

- Code is formatted using `yamlfmt`, `shfmt` and `rumdl`
- Code is linted using `shellcheck`, `rumdl`, `zizmor` and `actionlint`
- To run formatting and fix autofixable issues: `task validate:fix`
- To run all static validation: `task validate:static` (same as `task
  validate` here - there are no tests)
- `task renovate:config:validate` validates the Renovate configs
  (`actions/renovate/renovate-global.json5` and `default.json`) against a
  real `renovate-config-validator`; it fetches `default.json` from GitHub as
  published, not from the working tree - see the task's `summary`.

See `README.md` for what this repository is and how the Renovate action,
reusable workflows and preset are laid out.
