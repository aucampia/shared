# shared

Shared tooling for `aucampia` repositories, organized as independently
versioned parts - things one repository publishes so every other repository
runs the same mechanics and policy instead of forking them per repo. See
[`SPEC.md`](SPEC.md) for what belongs here and how a new part is added, and
[`CONTRIBUTING.md`](CONTRIBUTING.md) for conventions.

## Layout

- `part/<name>/` - one shared subsystem: a `README.md` (how to use it), a
  `SPEC.md` (how it works), and a versioned `v<N>/` implementation. See
  [`SPEC.md`](SPEC.md) for the pattern.
- `.github/workflows/` - reusable workflow definitions
  (`<name>-v<N>.yml`) and this repository's own thin local callers
  (`<name>.yml`), plus `validate.yml`. Reusable workflows have to live here
  rather than under `part/` - GitHub does not support them in
  subdirectories.
- `Taskfile.yml` - `task validate*` for linting this repository, plus each
  part's own tasks via `includes:`.

## Parts

- [Renovate](part/renovate/README.md) - self-hosted Renovate: a composite
  action, a reusable workflow, and a shareable preset.

## Verification

```bash
task configure
task validate  # yamlfmt, shfmt, shellcheck, rumdl, zizmor, actionlint, and
                # each part's own config validation
```
