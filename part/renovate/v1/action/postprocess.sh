#!/usr/bin/env bash

# This script performs post-processing on the pull requests Renovate has
# open after a run: any that is not approved yet gets approved, so that
# `platformAutomerge` can merge it.

set -Eeuo pipefail

REPORT_FILE="${RENOVATE_REPORT_PATH:-/tmp/renovate/report.json}"
RENOVATE_AUTO_APPROVE="${RENOVATE_AUTO_APPROVE:-false}"
RENOVATE_DRY_RUN="${RENOVATE_DRY_RUN:-}"

if [ -n "${RENOVATE_DRY_RUN}" ]; then
    echo "Not postprocessing as RENOVATE_DRY_RUN is ${RENOVATE_DRY_RUN@Q}" >&2
    exit 0
fi

# Renovate writes the report at the end of its run, so a missing or shapeless
# one means the run did not get far enough for postprocessing to be meaningful.
# Failing here beats silently approving nothing, which is the failure mode this
# script is meant to stop having.
if ! jq -e '.repositories | type == "object"' "${REPORT_FILE}" >/dev/null; then
    echo "No usable .repositories in ${REPORT_FILE}" >&2
    exit 1
fi

github_api() {
    curl --silent --fail-with-body -L \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer ${RENOVATE_GITHUB_ACTIONS_TOKEN}" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "${@}" </dev/null
}

# Every branch Renovate handled this run that has a PR. Approval is keyed off
# the report rather than off the branches Renovate pushed, because Renovate
# opens a PR without pushing when the branch is already up to date from an
# earlier run - a PR opened that way would otherwise never be approved. No
# `-e`: a run with nothing to update produces no lines, which is not an error.
# Branches without a `prNo` - the PR is still blocked by `prConcurrentLimit`,
# or Renovate only updated the branch - have nothing to approve.
jq -c '
    .repositories | to_entries | .[] | .key as $repository |
    .value.branches[] | select(.prNo != null) |
    {"repository": $repository, "branch": .branchName, "prNo": .prNo}' \
    "${REPORT_FILE}" >/tmp/renovate/branches-with-prs.ndjson

echo "Postprocessing these branches:" >&2
cat /tmp/renovate/branches-with-prs.ndjson >&2

errors=false

while IFS= read -r line; do
    echo "Postprocessing branch: ${line}" >&2
    REPOSITORY="$(jq -er '.repository' <<<"${line}")"
    BRANCH="$(jq -er '.branch' <<<"${line}")"
    PR_NUMBER="$(jq -er '.prNo' <<<"${line}")"
    declare -p REPOSITORY BRANCH PR_NUMBER >&2

    if [ "${RENOVATE_AUTO_APPROVE}" != "true" ]; then
        echo "Not auto-approving PR for branch: ${BRANCH} ${PR_NUMBER} as RENOVATE_AUTO_APPROVE is ${RENOVATE_AUTO_APPROVE@Q} and not 'true'" >&2
        continue
    fi

    PR_URL="https://api.github.com/repos/${REPOSITORY}/pulls/${PR_NUMBER}"

    if ! PR_JSON="$(github_api "${PR_URL}")"; then
        echo "Failed to read PR ${PR_NUMBER}: ${PR_JSON}" >&2
        errors=true
        continue
    fi

    # A PR that was merged or closed between Renovate writing the report and
    # this loop running has nothing to approve, and a draft cannot automerge.
    if ! jq -e '.state == "open" and (.draft | not)' >/dev/null <<<"${PR_JSON}"; then
        echo "Not auto-approving PR ${PR_NUMBER} for branch ${BRANCH} as it is $(jq -er '"state=\(.state) draft=\(.draft)"' <<<"${PR_JSON}")" >&2
        continue
    fi

    if ! REVIEWS_JSON="$(github_api "${PR_URL}/reviews?per_page=100")"; then
        echo "Failed to read reviews of PR ${PR_NUMBER}: ${REVIEWS_JSON}" >&2
        errors=true
        continue
    fi

    # Anything other than a bare comment means a review already happened, and
    # this script does not get to overrule it. "APPROVED" would just pile up a
    # duplicate review on a long-lived PR. "DISMISSED" is deliberate: a
    # ruleset with `dismiss_stale_reviews_on_push: false` (which is what every
    # consumer of this action is expected to use - see README.md "Ruleset
    # compatibility") treats a dismissal as someone withdrawing an approval by
    # hand, and re-approving it on the next run would merge the PR they were
    # holding back. A repository that does dismiss stale reviews on push wants
    # a human to look anyway.
    if jq -e 'any(.[]; .state == "APPROVED" or .state == "CHANGES_REQUESTED" or .state == "DISMISSED")' >/dev/null <<<"${REVIEWS_JSON}"; then
        echo "Not auto-approving PR ${PR_NUMBER} for branch ${BRANCH} as it was already reviewed: $(jq -erc '[.[] | select(.state != "COMMENTED" and .state != "PENDING") | "\(.user.login):\(.state)"]' <<<"${REVIEWS_JSON}")" >&2
        continue
    fi

    echo "Auto-approving PR for branch: ${BRANCH} ${PR_NUMBER}" >&2
    if ! RESPONSE="$(github_api -X POST "${PR_URL}/reviews" \
        -d '{"body":"Auto-approve by workflow.","event":"APPROVE"}')"; then
        echo "Failed to approve PR ${PR_NUMBER}: ${RESPONSE}" >&2
        errors=true
        continue
    fi
    echo "${RESPONSE}" >&2

done < <(sort -u <"/tmp/renovate/branches-with-prs.ndjson")

if [ "${errors}" = true ]; then
    exit 1
fi
