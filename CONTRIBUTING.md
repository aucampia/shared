# Contributing

## Tooling

- `mise` pins every dev tool (see `.mise.toml` / `mise.lock`); `task
  configure` runs `mise install`.
- `task` is the task runner. Root `Taskfile.yml` carries `validate*`;
  `part/<name>/Taskfile.yml` files are included into it under the part's
  own name (`task renovate`, `task renovate:dry-run`, and so on - see
  [`SPEC.md`](SPEC.md)).
- `task validate:fix` runs every autofixer; `task validate:static` (same as
  `task validate` here - no tests) runs every check.

## Code conventions

Observed in this repository; write new code to match rather than
introducing a different style.

### Shell (`part/*/v1/**/*.sh`)

- `#!/usr/bin/env bash`, then `set -Eeuo pipefail` - repeated inside any
  heredoc'd `bash -c` block too, since `set` does not propagate into one.
- A header comment block: a blank line after the shebang, a short paragraph
  on what the script does and how it fits in, then for a script with
  environment inputs a `# Inputs (all via environment):` block listing each
  `NAME`, its meaning, and whether it is required or its default.
- Required inputs: `: "${VAR:?message}"`. Optional inputs:
  `VAR="${VAR:-default}"`. Chained fallback:
  `"${A:-${B:-}}"`.
- Always brace variable expansions (`"${VAR}"`, never `$VAR`). `[ ]` over
  `[[ ]]`, with `==` inside `[`. `--` before path arguments
  (`dirname -- "${x}"`). Command prefixes as arrays, expanded
  `"${ARR[@]}"`. Herestrings and redirects with no space
  (`<<<"${VAR}"`, `>&2`).
- `declare -p VAR ... >&2` to dump state for debugging;
  `${VAR@Q}` for safely quoting a value inside a message.
- An inline `# shellcheck disable=SC____ # reason` where a warning is a
  false positive, never a bare disable.
- 4-space indent, enforced by `.editorconfig` rather than a `shfmt` flag -
  `shfmt` is invoked with no formatting flags precisely so it reads that
  file (`[*.sh]` in `.editorconfig` is deliberately commented out, so the
  `[*]` block's `indent_size = 4` applies).

### YAML

- 2-space indent (`.editorconfig`'s `*.{yaml,yml,json}` override).
  `.yamlfmt.yaml` otherwise uses the formatter's defaults - no configured
  line width.
- A `#` header comment at the top of a workflow or compose file explaining
  why it exists and how it relates to its siblings.
- Every `permissions:` entry carries a trailing `# reason` comment.
  Third-party actions are pinned to a full commit SHA with a trailing
  `# vN` comment.
- `workflow_call` inputs document their accepted values in `description:`
  (e.g. `description: enabled | disabled | reset`), folding longer prose
  with `>-`. `workflow_dispatch` inputs use `type: choice` with
  `options:` instead.
- A job's key equals its `name:`. A step that matters gets a `name:`; a
  glue step that is just a `uses:` is left unnamed.
- `desc:` on every Task task; `summary:` (a longer `|` block) on the ones
  whose behaviour isn't obvious from the name.

### Markdown

- 80-column prose (`.rumdl.toml`'s `[MD013]`, `reflow = true` - `task
  validate:fix` re-wraps automatically, so don't hand-wrap around a path or
  identifier that might change length later).
- ATX headings (`##`), `-` bullets, ordered lists as `1.` `2.`, backticked
  paths and identifiers, bare URLs in angle brackets.
- Bulleted lists with a `:` divider instead of tables.

## Where new work goes

Adding a new shared subsystem, or restructuring an existing one, follows
the pattern in [`SPEC.md`](SPEC.md).
