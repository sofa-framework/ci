#!/bin/bash
set -o errexit # Exit on error
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
. "$SCRIPT_DIR"/utils.sh
. "$SCRIPT_DIR"/dashboard.sh # needed for dashboard-config-string()

github-notify() {
    local state="$1"
    local message="$2"

    local options="$-"
    local notify="not sent"
    local response=""

    set +x # Private stuff here: echo disabled
    if [[ "$GITHUB_NOTIFY" == "true" ]] &&
       [ -n "$GITHUB_CONTEXT" ] &&
       [ -n "$GITHUB_TARGET_URL" ] &&
       [ -n "$GITHUB_REPOSITORY" ] &&
       [ -n "$GITHUB_COMMIT_HASH" ] &&
       [ -n "$GITHUB_SOFABOT_TOKEN" ]; then
        local request="{
            \"context\": \"$GITHUB_CONTEXT\",
            \"state\": \"$state\",
            \"description\": \"$message\",
            \"target_url\": \"$GITHUB_TARGET_URL\"
        }"

        response="$(curl --silent --header "Authorization: token $GITHUB_SOFABOT_TOKEN"  --data "$request" "https://api.github.com/repos/$GITHUB_REPOSITORY/statuses/$GITHUB_COMMIT_HASH")"
        if [ -n "$response" ]; then
            notify="sent"
        fi
    fi
    set -$options

    echo "Notify GitHub ($notify): [$state] $GITHUB_CONTEXT - $message"
    if [ -n "$response" ]; then
        echo "GitHub reponse: $response"
    fi
}

github-export-vars() {
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

    if in-array "report-to-github" "$build_options"; then
        export GITHUB_NOTIFY="true"
    else
        export GITHUB_NOTIFY="false"
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
            echo "Fallback value for git_url: $git_url"
        fi

        export GITHUB_REPOSITORY="$( echo "$git_url" | sed "s/.*github.com\/\(.*\)\.git/\1/g" )"
    fi

    if [ -z "$GITHUB_TARGET_URL" ]; then
        if [ -n "$BUILD_URL" ]; then
            export GITHUB_TARGET_URL="$BUILD_URL"
        else
            export GITHUB_TARGET_URL="#"
        fi
    fi

    if [ -n "$CHANGE_ID" ]; then # this is a PR
        local options="$-"
        set +x # Private stuff here: echo disabled    
        if [ -n "$GITHUB_SOFABOT_TOKEN" ] &&
           [ -n "$GITHUB_REPOSITORY" ]; then
            response="$(curl --silent --header "Authorization: token $GITHUB_SOFABOT_TOKEN" "https://api.github.com/repos/$GITHUB_REPOSITORY/pulls/$CHANGE_ID")"
            if [ -n "$response" ]; then
                local prev_pwd="$(pwd)"
                cd "$SCRIPT_DIR"
                export GITHUB_COMMIT_HASH="$( echo "$response" | python -c "import sys,githubJsonParser; githubJsonParser.get_head_sha(sys.stdin)" )"
                cd "$prev_pwd"
            fi
        fi
        set -$options
    elif [ -n "$GIT_COMMIT" ]; then
        export GITHUB_COMMIT_HASH="$GIT_COMMIT"
    else # This should not happen with Jenkins
        export GITHUB_COMMIT_HASH="$(git log --pretty=format:'%H' -1)"
        echo "Trying to guess GITHUB_COMMIT_HASH: $GITHUB_COMMIT_HASH"
    fi

    local options="$-"
    set +x # Private stuff here: echo disabled
    if [ -n "$GITHUB_SOFABOT_TOKEN" ] &&
       [ -n "$GITHUB_REPOSITORY" ] &&
       [ -n "$GITHUB_COMMIT_HASH" ]; then
        response="$(curl --silent --header "Authorization: token $GITHUB_SOFABOT_TOKEN" "https://api.github.com/repos/$GITHUB_REPOSITORY/commits/$GITHUB_COMMIT_HASH")"
        if [ -n "$response" ]; then
            local prev_pwd="$(pwd)"
            cd "$SCRIPT_DIR"
            export GITHUB_COMMIT_MESSAGE="$( echo "$response" | python -c "import sys,githubJsonParser; githubJsonParser.get_commit_message(sys.stdin)" )"
            export GITHUB_COMMIT_AUTHOR="$( echo "$response" | python -c "import sys,githubJsonParser; githubJsonParser.get_commit_author(sys.stdin)" )"
            export GITHUB_COMMIT_DATE="$( echo "$response" | python -c "import sys,githubJsonParser; githubJsonParser.get_commit_date(sys.stdin)" )"
            cd "$prev_pwd"
        fi
    fi
    set -$options

    if [ -n "$platform" ]; then    
        export GITHUB_CONTEXT="$(dashboard-config-string "$platform" "$compiler" "$architecture" "$build_type" "$build_options")"
    fi

    echo "GitHub env vars:"
    env | grep "^GITHUB_"
    echo "---------------------"
}
