# Renovate: how it works

Developer-facing. See [`README.md`](README.md) for how to *use* this part;
this document is about the machinery underneath.

## Run flow

`v1/action/action.yml` (composite action, `using: composite`) is the one
entry point both CI and local runs go through:

1. `renovate.yml` (root, `workflow_call`) or a consumer's copy of
   `v1/templates/renovate.yml` calls `renovate-v1.yml` (root,
   `workflow_call`), which checks out `aucampia/shared` into
   `.github/_shared` and runs `uses: ./.github/_shared/part/renovate/v1/action`.
   `renovate-v1.yml` itself is deliberately thin - just the two checkouts
   and the action call - so that everything CI-specific (restoring and
   exporting the repository cache, uploading the report) lives in
   `v1/action/action.yml` instead. Locally, `task renovate` calls
   `v1/action/run.sh` directly - same script, no composite-action wrapper,
   and no GitHub Actions artifacts to restore or export.
2. `v1/action/action.yml` restores the repository cache artifact (CI only,
   see "Cache and report round trip" below), then runs `v1/action/run.sh`.
3. `v1/action/run.sh` resolves the global config file (see "Config
   resolution" below), then drives
   `docker compose -f v1/action/docker-compose.yaml` to run the `renovate`
   service: validate the config with `renovate-config-validator --strict`,
   optionally restore the repository cache, run Renovate, export the cache,
   and copy out `report.json`.
4. Inside the container, `v1/action/entrypoint.sh` sources the env Renovate
   itself sets up, runs `renovate`, then runs `v1/action/postprocess.sh`.
5. `v1/action/postprocess.sh` reads the report Renovate just wrote and,
   when `RENOVATE_AUTO_APPROVE=true`, approves every open, unreviewed PR
   via the GitHub API, so `platformAutomerge` (set in `v1/default.json`)
   can merge it. It never signs anything - see `README.md` "Ruleset
   compatibility" for what a repository's branch ruleset needs as a
   result.
6. Back in `v1/action/action.yml`, once `run.sh` returns, it exports the
   cache and uploads the report as GitHub Actions artifacts (CI only).

## Container mounts

`v1/action/docker-compose.yaml` bind-mounts two things into the `renovate`
service, and the distinction between them matters for config resolution:

- `.:/srv/action:ro` - **this action's own directory**, i.e.
  `part/renovate/v1/action/`, wherever it was checked out. Read-only:
  nothing Renovate does should write into the action's own source.
- `${RENOVATE_WORKSPACE}:/srv/workspace` - **the caller's checkout**, the
  repository actually being renovated. Read-write (Renovate writes into it
  when not in dry-run mode).

A path meant to reach the caller's repository must resolve under
`/srv/workspace`; a path under `/srv/action` reaches this action's own
files instead, regardless of what the caller intended. This was a real bug
once: an earlier version of `RENOVATE_CONFIG_FILE_OVERRIDE` mapped its
container path under `/srv/action` even though the input is documented as
"absolute path inside the caller's checkout" - see the git history of
`v1/action/run.sh` for the fix.

## Config resolution precedence

`v1/action/run.sh` resolves `RENOVATE_CONFIG_FILE` (the file
`renovate-config-validator` and Renovate itself load) in this order:

1. **`RENOVATE_CONFIG_FILE_OVERRIDE`** (the action's `config-file` input) -
   an absolute path that must be inside `RENOVATE_WORKSPACE`. `run.sh`
   validates this with a `case` match against `"${RENOVATE_WORKSPACE}"/*`
   and maps it to the same relative path under `/srv/workspace`, preserving
   subdirectories. A path outside the workspace fails fast with a clear
   error rather than silently resolving to the wrong file. This is the
   *only* input that can point somewhere other than `renovate-global.json5`
   at a fixed location.
2. **`${RENOVATE_WORKSPACE}/renovate-global.json5`** - if the repository
   being renovated has one at its root, it wins in full. There is no
   merging with `v1/action/renovate-global.json5`; a repository that wants
   to tweak policy without replacing the whole self-hosted config should
   extend `github>aucampia/shared//part/renovate/v1/default.json` from its
   own config instead (the normal Renovate way), not replace the global
   config.
3. **`v1/action/renovate-global.json5`** (this repository's default) - used
   when neither of the above applies. This is what most consumer
   repositories get.

## Cache and report round trip

- **Repository cache** (`RENOVATE_REPOSITORY_CACHE`, default `enabled`):
  `run.sh` imports `RENOVATE_CACHE_ARCHIVE` (a `tar.gz`) into the
  container's `/tmp/renovate/cache` before the run and exports it back out
  after, so a scheduled run's cache survives to the next one. In CI this
  round-trips through an `actions/upload-artifact` /
  `dawidd6/action-download-artifact` pair keyed on the fixed name
  `renovate-cache`, both steps living in `v1/action/action.yml` (not the
  reusable workflow); a dry run does not upload its cache, so a branch
  under test cannot poison the scheduled run's cache.
- **Report** (`RENOVATE_REPORT_FILE`): `run.sh` copies
  `/tmp/renovate/report.json` out of the container unconditionally after
  every run (not just successful ones); `v1/action/action.yml` then
  uploads it as the `renovate-report` artifact, which `task
  renovate:gha:run` downloads for inspection.

## Versioning

`v1/` is the current, and so far only, version. A change to `action.yml`'s
inputs/outputs, `run.sh`'s environment contract, or `default.json`'s
resolution path that would break an existing consumer gets a `v2/`
alongside `v1/` (not a replacement) - see the repository root
[`SPEC.md`](../../SPEC.md) for the general rule. `v1/` keeps working for
anyone still pinned to it; nothing here auto-upgrades a consumer.

A non-breaking change (a new optional input, a bug fix that does not change
documented behaviour, a policy tweak in `default.json`) lands in `v1/`
directly.
