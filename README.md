# shared

Shared GitHub Actions tooling for `aucampia` repositories. The first (and so
far only) thing in here is a self-hosted Renovate setup: a composite action,
a reusable workflow, and a shareable Renovate preset, so every repository
runs the same Renovate mechanics and policy instead of forking them per
repo. This repository renovates itself through the same reusable workflow
it publishes - see `.github/workflows/renovate.yml`.

## Layout

- `actions/renovate/` - the composite action (`action.yml`), the Docker
  Compose service and entrypoint that run Renovate, the auto-approve
  postprocessor, and the default self-hosted global config
  (`renovate-global.json5`).
- `default.json` - the Renovate shareable preset (`github>aucampia/shared`)
  carrying the repo-config policy: labels, automerge, enabled managers,
  lockfile maintenance, and so on.
- `.github/workflows/renovate-reusable.yml` - the `workflow_call` entry
  point consumer repositories `uses:`.
- `.github/workflows/renovate.yml` - dogfoods the above against this
  repository itself.
- `.github/workflows/renovate-env.yml` - extracts Renovate's tokens
  (GPG-encrypted) for a local run; dual-triggered (`workflow_dispatch` +
  `workflow_call`) so it is both directly dispatchable here and reusable
  elsewhere.
- `templates/` - files to copy into a consumer repository: a thin
  `renovate.yml` / `renovate-env.yml` caller, and an optional Taskfile
  snippet for repos that want `task renovate` to work from their own
  checkout.
- `Taskfile.yml` - `task renovate*` tasks for running and testing all of the
  above locally, plus `task validate*` for linting this repository.

## Adopting this in a repository

1. Copy `templates/renovate.yml` to `.github/workflows/renovate.yml`.
2. Set a `RENOVATE_TOKEN` secret on the repository (see "Token handling").
3. Optionally, add a `renovate-global.json5` at the repository root to
   replace the default global config entirely (see "Config resolution"),
   or copy `templates/renovate-taskfile-snippet.yml`'s task into the
   repository's own `Taskfile.yml` for a same-repo `task renovate`.
4. Confirm the repository's branch ruleset is compatible with
   automerge - see "Ruleset compatibility".

## Config resolution

The action resolves the self-hosted global config file per run: if the
workspace being renovated has its own `renovate-global.json5` at its root,
that file is used verbatim, in full; otherwise
`actions/renovate/renovate-global.json5` (this repository's default) is
used. There is no merging between the two - a repository that wants to
override policy without replacing the whole self-hosted config should
instead extend `github>aucampia/shared` from its own config and override
individual keys, the normal Renovate way.

## Policy

`default.json` is the repo-config layer every repository gets by default
(via `globalExtends` in the global config - see the comment in
`actions/renovate/renovate-global.json5` for why `globalExtends` rather than
`extends`). A few choices are non-obvious enough to write down here, since a
preset file cannot carry comments:

- `extends: ["config:recommended", "security:minimumReleaseAgePypi"]` -
  direct PyPI version bumps have to be 3 days old before Renovate proposes
  them, so a yanked or compromised release has time to be pulled. The
  preset's `internalChecksFilter: "strict"` filters the candidate out
  entirely instead of parking a PR, which matters here: everything
  automerges, so a parked PR would just hold a `prConcurrentLimit` slot for
  three days. This covers updates that edit a `pyproject.toml` constraint,
  which under `rangeStrategy: "replace"` below is every PR the `pep621`
  manager raises. In-range and transitive bumps arrive through
  `lockFileMaintenance` instead, which the preset exempts outright:
  `uv lock --upgrade` (or the Go/npm/Terraform equivalent) takes whatever is
  newest at lock time, with no age check at all.
- `packageRules: [{matchManagers: ["pep621"], rangeStrategy: "replace"}]` -
  not `"update-lockfile"`: `rangeStrategy` and `lockFileMaintenance` are
  separate code paths that do not consider one another, so
  `"update-lockfile"` raises a lockfile-only PR per in-range bump while
  `lockFileMaintenance` rewrites the same lockfile wholesale - the two
  collide on every run, and `rebaseWhen: "conflicted"` only unblocks the
  loser a day later. `"replace"` raises a PR only when the new version falls
  outside the constraint, editing the manifest and lockfile together;
  everything in range is left to `lockFileMaintenance`, which is then the
  only writer of the lockfile on all other days. No-op in a repository with
  no `pyproject.toml`.
  <https://github.com/renovatebot/renovate/discussions/19285>
- `statusCheckWhen.artifactError: "always"` - by default Renovate only posts
  the artifact status check when an artifact update failed, so a green
  result never exists and the check can't be made required. `"always"`
  posts green too, so a lockfile Renovate failed to refresh can block the
  merge instead of riding along with `platformAutomerge`.
- `dependencyDashboardOSVVulnerabilitySummary: "unresolved"` - the enum is
  `"none" | "all" | "unresolved"`; `true` is silently rejected by config
  validation.
- `enabledManagers` covers `pep621`, `github-actions`, `docker-compose`,
  `dockerfile`, `mise`, `gomod`, `terraform`, `npm`, `nvm` - the toolchains
  in use across `aucampia` repositories today. A repository that needs a
  manager outside this list extends `github>aucampia/shared` from its own
  config and adds to `enabledManagers` there.

## Ruleset compatibility

`postprocess.sh` gets `platformAutomerge` moving by approving Renovate's own
PRs via the API - it does not sign anything. A repository's branch ruleset
therefore needs:

- `required_approving_review_count` satisfiable by a bot API approval (not
  `required_signatures`, which rejects Renovate's unsigned commits outright
  - a ruleset with that rule needs a human to merge Renovate PRs instead).
- `dismiss_stale_reviews_on_push: false` - `postprocess.sh` treats a
  dismissed review as a human deliberately withdrawing approval (see the
  comment above the check in `actions/renovate/postprocess.sh`) and will
  never re-approve after that. A ruleset that dismisses stale reviews on
  push wants a human to look at every push anyway.

## Token handling

`aucampia` is a personal account, not an organization, so there is no
org-level Actions secret - `RENOVATE_TOKEN` has to be set per repository for
CI. `task renovate:update-token` mints a fine-grained PAT (pre-filled URL
included) and stores it as that repository's Actions secret by default.

Separately, `TARGET=codespaces` stores the *same kind* of PAT as an
account-wide Codespaces secret, for local runs only - GitHub Actions cannot
read Codespaces secrets, so it does not substitute for the per-repo Actions
secret above. Set once, it is picked up by `task renovate` in any Codespace
with no per-repo step, since `actions/renovate/run.sh` reads the token from
the environment and never shells out to `gh`. Two things this needs that the
default path does not:

- The `codespace` OAuth scope on your `gh` token
  (`gh auth refresh -s codespace`) - without it, `gh secret set --user`
  fails with a misleading "Must have admin rights to Repository.", which is
  actually a missing-scope error, not a permissions one.
- A `REPOS=repo1,repo2,...` list of every repository that should see the
  secret, comma-separated, on *every* invocation -
  `gh secret set --user --repos` replaces the repository list rather than
  adding to it, so omitting a previously-added repository drops its access.

## Local runs

Primary path - from this checkout, against any repository on disk:

```bash
export RENOVATE_TOKEN="$(gh auth token)"
RENOVATE_WORKSPACE=~/code/aucampia/signalsmith task renovate
```

`task renovate:dry-run` wraps the same call with
`RENOVATE_DRY_RUN=full RENOVATE_LOG_LEVEL=debug` and tees the output to
`renovate-output.log`.

Secondary path - a `task renovate` that works from the target repository's
own checkout: copy the task in `templates/renovate-taskfile-snippet.yml`
into that repository's `Taskfile.yml`.

`task renovate:gha:run [REPO=aucampia/<repo>]` dispatches and watches
`.github/workflows/renovate.yml` on the current branch of *this*
repository, for the given target repository's `renovate.yml` (default: this
repository, i.e. dogfooding). `task renovate:env:run [REPO=...] -- <cmd>`
extracts real CI tokens for a local run against a specific repository's
workflow.

## Verification

```bash
task configure
task validate                  # yamlfmt, shfmt, shellcheck, rumdl, zizmor, actionlint
task renovate:config:validate  # renovate-config-validator --strict
```
