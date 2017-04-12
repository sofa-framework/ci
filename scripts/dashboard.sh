#!/bin/bash
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
. "$SCRIPT_DIR"/utils.sh

dashboard-notify() {
    local message="sha=$DASH_COMMIT_HASH&config=$DASH_CONFIG"
    while [ $# -gt 0 ]; do
        message="$message&$1"
        shift
    done
    if [ "$DASH_REPORT_TO_DASHBOARD" = "true" ] && [ -n "$DASH_DASHBOARD_URL" ]; then
        echo "Notify dashboard (sent): $message"
        # wget --no-check-certificate --no-verbose --output-document=/dev/null --post-data="$message" "$DASH_DASHBOARD_URL"
    else
        echo "Notify dashboard (not sent): $message"
    fi
}

dashboard-init() {
    echo "DASH: Create/update commit line"
    dashboard-notify "comment=$DASH_COMMIT_MESSAGE" "date=$DASH_COMMIT_DATE" "author=$DASH_COMMIT_AUTHOR" "branch=$DASH_COMMIT_BRANCH"

    echo "DASH: Create/update build frame with empty status"
    if in-array "force-full-build" "$BUILD_OPTIONS"; then
        dashboard-notify "fullbuild=true" "build_url=$BUILD_URL" "job_url=$JOB_URL" "status="
    else
        dashboard-notify "build_url=$BUILD_URL" "job_url=$JOB_URL" "status="
    fi
}

dashboard-export-vars() {
    local COMPILER="$1"
    local ARCHITECTURE="$2"
    local BUILD_TYPE="$3"
    local BUILD_OPTIONS="$4"
    
    if in-array "report-to-dashboard" "$BUILD_OPTIONS"; then
        export DASH_REPORT_TO_DASHBOARD="true"
    fi

    export DASH_COMMIT_HASH="$(git log --pretty=format:'%H' -1)"
    export DASH_COMMIT_AUTHOR="$(git log --pretty=format:'%an' -1)"
    # author_email=$(git log --pretty=format:'%aE' -1)
    # committer=$(git log --pretty=format:'%cn' -1)
    # committer_email=$(git log --pretty=format:'%cE' -1)
    export DASH_COMMIT_DATE="$(git log --pretty=format:%ct -1)"
    export DASH_COMMIT_MESSAGE="$(git log --pretty=format:'%s' -1)"
    # subject_full=$(git log --pretty=%B -1)
    if [ -n "$GIT_BRANCH" ]; then # Check Jenkins env var first
        export DASH_COMMIT_BRANCH="$GIT_BRANCH"
    else
        export DASH_COMMIT_BRANCH="$(git branch | grep \* | cut -d ' ' -f2)"
    fi
    
    # DASH_PLATFORM = [mac, ubuntu, centos, winxp, windows7, windows7-64]
    if [ -n "$CI_PLATFORM" ]; then # Check Jenkins env var first
        export DASH_PLATFORM="$CI_PLATFORM"
    else
        case "$OSTYPE" in
            darwin*)      export DASH_PLATFORM="mac" ;; 
            linux-gnu*)   export DASH_PLATFORM="$(cat /etc/os-release | grep "^ID=" | cut -d "=" -f 2)" ;;
            msys*)        export DASH_PLATFORM="windows7" ;;
            *)            export DASH_PLATFORM="$OSTYPE" ;;
        esac
    fi

    # DASH_OPTIONS = [default, options, default-debug, options-debug]
    if in-array "build-all-plugins" "$BUILD_OPTIONS"; then
        export DASH_OPTIONS="options"
    else
        export DASH_OPTIONS="default"
    fi
    if [ "$BUILD_TYPE" = "Debug" ]; then
        export DASH_OPTIONS="$DASH_OPTIONS"-debug
    fi
    
    # DASH_CONFIG
    export DASH_CONFIG="$DASH_PLATFORM"_"$COMPILER"_"$DASH_OPTIONS"
    if [[ "$DASH_PLATFORM" == *"windows"* ]] && [ "$ARCHITECTURE" = "amd64" ]; then
        export DASH_CONFIG="$DASH_CONFIG"_"$ARCHITECTURE"
    fi
    
    # DASH_DASHBOARD_URL
    if [ -z "$DASH_DASHBOARD_URL" ]; then
        export DASH_DASHBOARD_URL="https://www.sofa-framework.org/dash/input.php"
    fi
}