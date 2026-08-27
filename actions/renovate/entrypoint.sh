#!/usr/bin/env bash

# Entrypoint for the `renovate` service in docker-compose.yaml. Replaces the
# Renovate image's own entrypoint - see the `entrypoint:` override next to
# where this is invoked for why.

set -Eeuo pipefail

declare -p LOG_LEVEL RENOVATE_REPOSITORY_CACHE RENOVATE_AUTO_APPROVE RENOVATE_DRY_RUN >&2

# Code below comes from:
# docker run --rm -i docker.io/renovate/renovate:latest cat /usr/local/sbin/renovate-entrypoint.sh
# docker run --rm -i docker.io/renovate/renovate:latest cat /usr/local/sbin/docker-entrypoint.sh

export GIT_TRACE=/tmp/renovate/git-trace.log
echo -n >/tmp/renovate/git-trace.log

dump_logs() {
    if [ "${LOG_LEVEL}" == "debug" ]; then
        echo "GIT_TRACE logs:" >&2
        cat /tmp/renovate/git-trace.log >&2
    fi
}

trap dump_logs EXIT

# shellcheck disable=SC1091 # only exists inside the renovate image
source /usr/local/etc/env
renovate

# /srv/action is the action directory (actions/renovate/), bind-mounted
# read-only - see docker-compose.yaml.
/srv/action/postprocess.sh

echo "Renovate finished successfully." >&2
