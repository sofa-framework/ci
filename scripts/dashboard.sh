#!/bin/bash
#set -o errexit # Exit on error
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
. "$SCRIPT_DIR"/utils.sh

dashboard-notify-explicit() {
    local message=""
    local notify="not sent"

    message="$1"; shift
    while [ $# -gt 0 ]; do
        message="$message&$1"; shift
    done

    if [[ "$DASH_FULLBUILD" == "true" ]]; then
        message="fullbuild=true&$message"
    else
        message="fullbuild=false&$message"
    fi

    if [[ "$DASH_NOTIFY" == "true" ]] && [ -n "$DASH_DASHBOARD_URL" ]; then
        if [ ! -e /tmp/cacert.pem ]; then
            echo "Curl certificate bundle not found. Downloading it from https://curl.haxx.se/ca/cacert.pe"
            curl --silent -L "https://curl.haxx.se/ca/cacert.pem" --output /tmp/cacert.pem
            ls -la /tmp/cacert.pem
        fi
        curl --silent --cacert "/tmp/cacert.pem" --data "$message" -X POST "$DASH_DASHBOARD_URL"
        notify="sent - curl returned $?"
    fi

    echo "Notify Dashboard ($notify): $message"
}

dashboard-notify() {
    dashboard-notify-explicit "sha=$DASH_COMMIT_HASH" "config=$DASH_CONFIG" "node=$NODE_NAME" "job_url=$JOB_URL" "build_url=$BUILD_URL" $*
}

dashboard-init() {
    echo "DASH: Create/update commit line"
    dashboard-notify-explicit "sha=$DASH_COMMIT_HASH" "base_sha=$DASH_BASECOMMIT_HASH" "comment=$DASH_COMMIT_SUBJECT" "date=$DASH_COMMIT_DATE" "author=$DASH_COMMIT_AUTHOR" "branch=$DASH_COMMIT_BRANCH"
}

dashboard-config-string() {
    local platform="$1"
    local compiler="$2"
    local architecture="$3"
    local build_type="$4"
    local build_options="$5"

    # suffix = [default, options, default-debug, options-debug]
    if in-array "build-all-plugins" "$build_options"; then
        suffix="options"
    elif in-array "build-release-package" "$build_options"; then
        suffix="package"
    else
        suffix="default"
    fi
    if [[ "$build_type" == "debug" ]]; then
        suffix="${suffix}-debug"
    fi

    # config building
    config="$platform"_"$compiler"_"$suffix"
    if [[ "$platform" == *"windows7"* ]]; then
        config="${config}_${architecture}"
    fi

    echo "$config"
}

dashboard-export-vars() {
    echo "Calling ${FUNCNAME[0]}"

    if [ "$#" -ge 5 ]; then
        local platform="$1"
        local compiler="$2"
        local architecture="$3"
        local build_type="$4"
        local build_options="$5"
    else
        local build_options="$1"
    fi

    if in-array "report-to-dashboard" "$build_options"; then
        export DASH_NOTIFY="true"
    else
        export DASH_NOTIFY="false"
    fi

    if in-array "force-full-build" "$build_options"; then
        export DASH_FULLBUILD="true"
    fi

    if [ -n "$CI_COMMIT_HASH" ]; then
        export DASH_COMMIT_HASH="$CI_COMMIT_HASH"
    elif [ -n "$GITHUB_COMMIT_HASH" ]; then
        export DASH_COMMIT_HASH="$GITHUB_COMMIT_HASH"
    else
        export DASH_COMMIT_HASH="$(git log --pretty=format:'%H' -1)"
        echo "Trying to guess DASH_COMMIT_HASH: $DASH_COMMIT_HASH"
    fi

    if [ -n "$CI_BASECOMMIT_HASH" ]; then
        export DASH_BASECOMMIT_HASH="$CI_BASECOMMIT_HASH"
    elif [ -n "$GITHUB_BASECOMMIT_HASH" ]; then
        export DASH_BASECOMMIT_HASH="$GITHUB_BASECOMMIT_HASH"
    fi

    if [ -n "$GITHUB_COMMIT_AUTHOR" ]; then
        export DASH_COMMIT_AUTHOR="$GITHUB_COMMIT_AUTHOR"
    else
        export DASH_COMMIT_AUTHOR="$(git log --pretty=format:'%an' -1)"
        echo "Trying to guess DASH_COMMIT_AUTHOR: $DASH_COMMIT_AUTHOR"
    fi

    if [ -n "$GITHUB_COMMIT_DATE" ]; then
        export DASH_COMMIT_DATE="$GITHUB_COMMIT_DATE"
    else
        export DASH_COMMIT_DATE="$(git log --pretty=format:%ct -1)"
        echo "Trying to guess DASH_COMMIT_DATE: $DASH_COMMIT_DATE"
    fi

    if [ -n "$GITHUB_COMMIT_MESSAGE" ]; then
        export DASH_COMMIT_SUBJECT="$(echo "$GITHUB_COMMIT_MESSAGE" | head -n 1)"
    else
        export DASH_COMMIT_SUBJECT="$(git log --pretty=format:'%s' -1)"
        echo "Trying to guess DASH_COMMIT_SUBJECT: $DASH_COMMIT_SUBJECT"
    fi

    if [ -n "$CI_BRANCH" ]; then # Check Jenkins env var first
        export DASH_COMMIT_BRANCH="$CI_BRANCH"
    elif [ -n "$GIT_BRANCH" ]; then # Check Jenkins env var first
        export DASH_COMMIT_BRANCH="$GIT_BRANCH"
    elif [ -n "$BRANCH_NAME" ]; then # Check Jenkins env var first
        export DASH_COMMIT_BRANCH="origin/$BRANCH_NAME"
    else # fallback: try to get the branch manually
        export DASH_COMMIT_BRANCH="$(git branch | grep \* | cut -d ' ' -f2)"
        echo "Trying to guess DASH_COMMIT_BRANCH: $DASH_COMMIT_BRANCH"
    fi

    # DASH_DASHBOARD_URL
    if [ -z "$DASH_DASHBOARD_URL" ]; then
        export DASH_DASHBOARD_URL="https://www.sofa-framework.org/dash/input.php"
    fi

    if [ -n "$platform" ]; then
        export DASH_CONFIG="$(dashboard-config-string "$platform" "$compiler" "$architecture" "$build_type" "$build_options")"
    fi

    echo "Dashboard env vars:"
    env | grep "^DASH_"
    echo "---------------------"
}
