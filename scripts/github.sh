#!/bin/bash
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
. "$SCRIPT_DIR"/utils.sh

github-notify() {
    local state="$1"
    local message="$2"

    local options="$-"
    local notify="not sent"

    set +x # Private stuff here: echo disabled
    if [[ "$GITHUB_NOTIFY" == "true" ]] && 
    [ -n "$GITHUB_CONTEXT" ] && 
    [ -n "$GITHUB_TARGET_URL" ] && 
    [ -n "$GITHUB_STATUS_URL" ] && 
    [ -n "$GITHUB_COMMIT_HASH" ] && 
    [ -n "$GITHUB_TOKEN" ]; then
        if [[ "$GITHUB_NOTIFY" == "true" ]]; then
            curl -i -H "Authorization: token $GITHUB_TOKEN"  -d '{
                "context": "'$GITHUB_CONTEXT'",
                "state": "'$state'",
                "description": "'$message'",
                "target_url": "'$GITHUB_TARGET_URL'"
            }' "${GITHUB_STATUS_URL}/${GITHUB_COMMIT_HASH}"
        fi
        notify="sent"
    fi
    set -$options

    echo "Notify GitHub ($notify): $GITHUB_CONTEXT: $message"
}

github-export-vars() {
    local build_options="$1"
    local context="$2"
    local target_url="$3"

    if in-array "report-to-github" "$BUILD_OPTIONS"; then
        export GITHUB_NOTIFY="true"
    fi

    if [ -n "$context" ]; then
        export GITHUB_CONTEXT="$context"
    else # env fallback
        export GITHUB_CONTEXT="$JOB_NAME"
    fi

    if [ -n "$target_url" ]; then 
        export GITHUB_TARGET_URL="$target_url"
    else # env fallback
        export GITHUB_TARGET_URL="$BUILD_URL"
    fi

    local subject_full="$(git log --pretty=%B -1)"
    local committer_name="$(git log --pretty=%cn -1)"
    if [[ "$JOB_NAME" == "PR-"* ]] || 
       [[ "$committer_name" == "GitHub" ]] && [[ "$subject_full" == "Merge "*" into "* ]]; then # this is a PR
        export GITHUB_COMMIT_HASH="$(git log --pretty=format:'%H' -2 | tail -1)" # skip merge commit
    else
        export GITHUB_COMMIT_HASH="$(git log --pretty=format:'%H' -1)"
    fi

    if [ -z "$GITHUB_STATUS_URL" ]; then
        export GITHUB_STATUS_URL="https://api.github.com/repos/sofa-framework/sofa/statuses"
    fi
}
