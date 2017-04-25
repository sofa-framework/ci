#!/bin/bash
set -o errexit # Exit on error
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
. "$SCRIPT_DIR"/utils.sh

github-notify() {
    local state="$1"
    local message="$2"

    local options="$-"
    local notify="not sent"

    set +x # Private stuff here: echo disabled
    if [ -n "$GITHUB_CONTEXT" ] && 
    [ -n "$GITHUB_TARGET_URL" ] && 
    [ -n "$GITHUB_REPOSITORY" ] && 
    [ -n "$GITHUB_COMMIT_HASH" ] && 
    [ -n "$GITHUB_TOKEN" ]; then
        if [[ "$GITHUB_NOTIFY" == "true" ]]; then
            local request="{
                \"context\": \"$GITHUB_CONTEXT\",
                \"state\": \"$state\",
                \"description\": \"$message\",
                \"target_url\": \"$GITHUB_TARGET_URL\"
            }"

            response="$(curl --silent --header "Authorization: token $GITHUB_TOKEN"  --data "$request" "https://api.github.com/repos/$GITHUB_REPOSITORY/statuses/$GITHUB_COMMIT_HASH")"
        fi
        notify="sent"
    fi
    set -$options

    echo "Notify GitHub ($notify): $GITHUB_CONTEXT: $message"
    if [[ "$notify" == "sent" ]]; then
        echo "GitHub reponse: $response"
    fi
}

github-export-vars() {
    local build_options="$1"
    export GITHUB_CONTEXT="$2"
    export GITHUB_TARGET_URL="$3"

    if in-array "report-to-github" "$build_options"; then
        export GITHUB_NOTIFY="true"
    fi

    if [ -z "$GITHUB_CONTEXT" ]; then
        if [ -n "$JOB_NAME" ]; then
            export GITHUB_CONTEXT="$JOB_NAME" # env fallback
        else 
            export GITHUB_CONTEXT="default"
        fi
    fi

    if [ -z "$GITHUB_TARGET_URL" ]; then
        if [ -n "$BUILD_URL" ]; then
            export GITHUB_TARGET_URL="$BUILD_URL" # env fallback
        fi
    fi

    local subject_full="$(git log --pretty=%B -1)"
    local committer_name="$(git log --pretty=%cn -1)"
    if [[ "$JOB_NAME" == "PR-"* ]] || 
       [[ "$committer_name" == "GitHub" ]] && [[ "$subject_full" == "Merge "*" into "* ]]; then # this is a PR
        export GITHUB_COMMIT_HASH="$(git log --pretty=format:'%H' -2 | tail -1)" # skip merge commit
    else
        export GITHUB_COMMIT_HASH="$(git log --pretty=format:'%H' -1)"
    fi

    if [ -z "$GITHUB_REPOSITORY" ]; then
        if [ -n "$GIT_URL_1" ]; then
            git_url="$GIT_URL_1"
        elif [ -n "$GIT_URL_2" ]; then
            git_url="$GIT_URL_2"
        elif [ -n "$GIT_URL" ]; then
            git_url="$GIT_URL"
        else
            git_url="https://github.com/sofa-framework/sofa.git"
        fi

        export GITHUB_REPOSITORY="$( echo "$git_url" | sed "s/.*github.com\/\(.*\)\.git/\1/g" )"
    fi
}
