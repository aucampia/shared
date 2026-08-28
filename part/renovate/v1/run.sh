#!/usr/bin/env bash

# Runs Renovate against a single workspace, driving the `renovate` service
# in the sibling docker-compose.yaml. This is the one code path shared by
# action.yml (CI) and `task renovate` (local) - see README.md.
#
# Inputs (all via environment):
#   RENOVATE_WORKSPACE          Absolute path to the repository to renovate.
#                                Required.
#   RENOVATE_TOKEN               Renovate's GitHub platform token. Required.
#   RENOVATE_GITHUB_ACTIONS_TOKEN Token used to approve PRs in postprocess.sh.
#                                Defaults to GITHUB_TOKEN.
#   RENOVATE_REPOSITORIES        Repository slug(s) to process. Defaults to
#                                the `owner/repo` derived from
#                                RENOVATE_WORKSPACE's git remote.
#   RENOVATE_CONFIG_FILE_OVERRIDE
#                                Absolute path to a global config file to use
#                                verbatim, skipping auto-resolution.
#   RENOVATE_REPOSITORY_CACHE    enabled | disabled | reset. Default enabled.
#   RENOVATE_LOG_LEVEL           Default info.
#   RENOVATE_AUTO_APPROVE        true | false. Default false.
#   RENOVATE_DRY_RUN             disabled | full | lookup | extract. Default
#                                disabled; mapped to an empty value for
#                                Renovate itself, which treats "not set" as
#                                "not a dry run" and has no "disabled" value
#                                of its own.
#   RENOVATE_CACHE_ARCHIVE        Local tar.gz to import/export the
#                                repository cache through. Default
#                                /tmp/renovate-cache.tar.gz.
#   RENOVATE_REPORT_FILE          Local path the run's report.json is copied
#                                to. Default /tmp/renovate-report.json.

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.yaml"
COMPOSE=(docker compose -f "${COMPOSE_FILE}" --project-name renovate-shared)

: "${RENOVATE_WORKSPACE:?RENOVATE_WORKSPACE must be set}"
RENOVATE_WORKSPACE="$(cd -- "${RENOVATE_WORKSPACE}" && pwd)"
: "${RENOVATE_TOKEN:?RENOVATE_TOKEN must be set}"
RENOVATE_GITHUB_ACTIONS_TOKEN="${RENOVATE_GITHUB_ACTIONS_TOKEN:-${GITHUB_TOKEN:-}}"
: "${RENOVATE_GITHUB_ACTIONS_TOKEN:?RENOVATE_GITHUB_ACTIONS_TOKEN or GITHUB_TOKEN must be set}"

RENOVATE_REPOSITORY_CACHE="${RENOVATE_REPOSITORY_CACHE:-enabled}"
RENOVATE_LOG_LEVEL="${RENOVATE_LOG_LEVEL:-info}"
RENOVATE_AUTO_APPROVE="${RENOVATE_AUTO_APPROVE:-false}"
RENOVATE_CACHE_ARCHIVE="${RENOVATE_CACHE_ARCHIVE:-/tmp/renovate-cache.tar.gz}"
RENOVATE_REPORT_FILE="${RENOVATE_REPORT_FILE:-/tmp/renovate-report.json}"

# Renovate only accepts extract/lookup/full for RENOVATE_DRY_RUN. "disabled"
# is a readable off switch for callers (workflow_dispatch choice inputs,
# Task) and becomes the empty value Renovate treats as "not a dry run".
RENOVATE_DRY_RUN_INPUT="${RENOVATE_DRY_RUN:-disabled}"
if [ "${RENOVATE_DRY_RUN_INPUT}" == "disabled" ]; then
    export RENOVATE_DRY_RUN=""
else
    export RENOVATE_DRY_RUN="${RENOVATE_DRY_RUN_INPUT}"
fi

if [ -n "${RENOVATE_REPOSITORIES:-}" ]; then
    : # explicit override
elif REMOTE_URL="$(git -C "${RENOVATE_WORKSPACE}" remote get-url origin 2>/dev/null)"; then
    RENOVATE_REPOSITORIES="$(sed -E 's#^(git@github\.com:|https://github\.com/)##; s#\.git$##' <<<"${REMOTE_URL}")"
else
    echo "RENOVATE_REPOSITORIES is not set and could not be derived from ${RENOVATE_WORKSPACE}'s origin remote" >&2
    exit 1
fi
export RENOVATE_REPOSITORIES

# Config resolution: the workspace's own renovate-global.json5 wins, so a
# consumer repository can fully replace the default global config; otherwise
# fall back to this action's default.
if [ -n "${RENOVATE_CONFIG_FILE_OVERRIDE:-}" ]; then
    CONFIG_FILE_HOST="${RENOVATE_CONFIG_FILE_OVERRIDE}"
    # Documented as "absolute path inside the caller's checkout" (see
    # config-file in action.yml / renovate-v1.yml), so it must resolve
    # under RENOVATE_WORKSPACE, which is what is bind-mounted into the
    # container as /srv/workspace - not /srv/action, which is this action's
    # own directory (a sibling of run.sh, unrelated to the caller's checkout).
    case "${CONFIG_FILE_HOST}" in
    "${RENOVATE_WORKSPACE}"/*)
        CONFIG_FILE_CONTAINER="/srv/workspace/${CONFIG_FILE_HOST#"${RENOVATE_WORKSPACE}"/}"
        ;;
    *)
        echo "RENOVATE_CONFIG_FILE_OVERRIDE (${CONFIG_FILE_HOST}) must be an absolute path inside RENOVATE_WORKSPACE (${RENOVATE_WORKSPACE})" >&2
        exit 1
        ;;
    esac
elif [ -f "${RENOVATE_WORKSPACE}/renovate-global.json5" ]; then
    CONFIG_FILE_HOST="${RENOVATE_WORKSPACE}/renovate-global.json5"
    CONFIG_FILE_CONTAINER="/srv/workspace/renovate-global.json5"
else
    CONFIG_FILE_HOST="${SCRIPT_DIR}/renovate-global.json5"
    CONFIG_FILE_CONTAINER="/srv/action/renovate-global.json5"
fi
export RENOVATE_CONFIG_FILE="${CONFIG_FILE_CONTAINER}"
echo "Using Renovate config: ${CONFIG_FILE_HOST} (${CONFIG_FILE_CONTAINER} in container)" >&2

export RENOVATE_TOKEN RENOVATE_GITHUB_ACTIONS_TOKEN RENOVATE_WORKSPACE
export RENOVATE_REPOSITORY_CACHE RENOVATE_LOG_LEVEL RENOVATE_AUTO_APPROVE

declare -p RENOVATE_REPOSITORIES RENOVATE_CONFIG_FILE RENOVATE_REPOSITORY_CACHE \
    RENOVATE_LOG_LEVEL RENOVATE_AUTO_APPROVE RENOVATE_DRY_RUN >&2

# Fail fast on a broken config instead of letting Renovate boot, log warnings
# about it and run with a half-applied config. No credentials needed, but
# compose interpolates RENOVATE_TOKEN/RENOVATE_GITHUB_ACTIONS_TOKEN into the
# service definition and warns when they are unset; --entrypoint="" bypasses
# entrypoint.sh, which the validator has no use for.
RENOVATE_TOKEN="" RENOVATE_GITHUB_ACTIONS_TOKEN="" \
    "${COMPOSE[@]}" run --entrypoint="" --quiet-build --quiet-pull -T --rm renovate \
    renovate-config-validator --strict "${CONFIG_FILE_CONTAINER}"

if [ "${RENOVATE_REPOSITORY_CACHE}" != "disabled" ] && [ -e "${RENOVATE_CACHE_ARCHIVE}" ]; then
    echo "Restoring cache from ${RENOVATE_CACHE_ARCHIVE}" >&2
    if "${COMPOSE[@]}" run --entrypoint="" --quiet-build --quiet-pull -T --rm renovate bash -c '
        set -Eeuo pipefail
        rm -rf /tmp/renovate/cache
        mkdir -p /tmp/renovate/cache
        exec tar -xzf - -C /tmp/renovate/cache .
    ' <"${RENOVATE_CACHE_ARCHIVE}"; then
        echo "Renovate cache imported successfully from ${RENOVATE_CACHE_ARCHIVE}." >&2
    else
        echo "Failed to import Renovate cache from ${RENOVATE_CACHE_ARCHIVE}, continuing without it." >&2
    fi
fi

"${COMPOSE[@]}" run --quiet-build --quiet-pull -T --rm renovate

if [ "${RENOVATE_REPOSITORY_CACHE}" != "disabled" ]; then
    mkdir -p "$(dirname -- "${RENOVATE_CACHE_ARCHIVE}")"
    "${COMPOSE[@]}" run --entrypoint="" --quiet-build --quiet-pull -T --rm renovate bash -c '
        set -Eeuo pipefail
        mkdir -p /tmp/renovate/cache >&2
        exec tar -czf - -C /tmp/renovate/cache .
    ' >"${RENOVATE_CACHE_ARCHIVE}.tmp"
    mv -v "${RENOVATE_CACHE_ARCHIVE}.tmp" "${RENOVATE_CACHE_ARCHIVE}"
    echo "Renovate cache exported successfully to ${RENOVATE_CACHE_ARCHIVE}." >&2
fi

mkdir -p "$(dirname -- "${RENOVATE_REPORT_FILE}")"
"${COMPOSE[@]}" run --entrypoint="" --quiet-build --quiet-pull -T --rm renovate \
    cat /tmp/renovate/report.json >"${RENOVATE_REPORT_FILE}"
echo "Renovate report exported successfully to ${RENOVATE_REPORT_FILE}" >&2
