# Spec

This repository holds tooling shared across `aucampia` repositories - things
one repository publishes so every other repository consumes the same
mechanics and policy instead of forking them per repo. See
[`README.md`](README.md) for the general overview and
[`CONTRIBUTING.md`](CONTRIBUTING.md) for conventions.

## Adding something new

Something new goes in `part/<name>/`, following the pattern `part/renovate/`
already uses:

- `part/<name>/README.md` - user-facing: what it is, how to adopt it.
- `part/<name>/SPEC.md` - developer-facing: how the machinery works.
- `part/<name>/v1/` - the versioned implementation. Everything that can live
  under the part - actions, scripts, config, consumer templates - does.
- `part/<name>/Taskfile.yml` (optional) - tasks specific to this part,
  included into the repository root `Taskfile.yml` under the part's own
  name.

Only what the platform genuinely cannot relocate stays at the repository
root: GitHub requires reusable workflows (`workflow_call`) at the top level
of `.github/workflows/` - a subdirectory reference is rejected outright -
so a part's reusable workflow lives there too, named
`.github/workflows/<name>-v<N>.yml`, with a thin same-named local caller
(`.github/workflows/<name>.yml`) dogfooding it. Repo-wide dev tooling
(`.mise.toml`, root `Taskfile.yml`, root `docker-compose.yaml`, `.github/`
itself) is not part-owned and stays where it is.

## Versioning

Each part is versioned independently, starting at `v1/`. A breaking change
to a part's inputs, outputs, or documented behaviour gets a new `v<N+1>/`
directory alongside the old one, not a replacement - existing consumers
pinned to `v<N>` keep working. A non-breaking change (new optional input,
bug fix, policy tweak) lands in the current version directly.

Reusable-workflow filenames and Renovate-preset paths carry the version
explicitly (`renovate-v1.yml`,
`github>aucampia/shared//part/renovate/v1/default.json`) for the same
reason: neither has another way to express "this is version 1."

## Parts

- [Renovate](part/renovate/SPEC.md) - self-hosted Renovate: action,
  reusable workflow, shareable preset.
