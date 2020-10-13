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
    # if [ -n "$response" ]; then
        # echo "GitHub reponse: $response"
    # fi
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

    local python_exe="python"
    if [ -n "$CI_PYTHON_CMD" ]; then
        python_exe="$CI_PYTHON_CMD"
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

    branch=""
    if [ -n "$CI_BRANCH" ]; then # Check Jenkins env var first
        branch="$CI_BRANCH"
    elif [ -n "$GIT_BRANCH" ]; then # Check Jenkins env var first
        branch="$GIT_BRANCH"
    elif [ -n "$BRANCH_NAME" ]; then # Check Jenkins env var first
        branch="origin/$BRANCH_NAME"
    fi

    if [ -n "$CI_COMMIT_HASH" ]; then
        export GITHUB_COMMIT_HASH="$CI_COMMIT_HASH"
    fi
    if [ -n "$CI_BASECOMMIT_HASH" ]; then
        export GITHUB_BASECOMMIT_HASH="$CI_BASECOMMIT_HASH"
    fi

    if [[ "$branch" == *"/PR-"* ]]; then # this is a PR
        local pr_id="${branch#*-}"
        local options="$-"
        set +x # Private stuff here: echo disabled
        if [ -n "$GITHUB_SOFABOT_TOKEN" ]; then
            response="$(curl --silent --header "Authorization: token $GITHUB_SOFABOT_TOKEN" "https://api.github.com/repos/$GITHUB_REPOSITORY/pulls/$pr_id")"
            if [ -n "$response" ]; then
                local prev_pwd="$(pwd)"
                cd "$SCRIPT_DIR"
                if [ -z "$GITHUB_COMMIT_HASH" ]; then
                    export GITHUB_COMMIT_HASH="$( echo "$response" | $python_exe -c "import sys,githubJsonParser; githubJsonParser.get_head_sha(sys.stdin)" )"
                fi
                export GITHUB_BASE_REF="$( echo "$response" | $python_exe -c "import sys,githubJsonParser; githubJsonParser.get_base_ref(sys.stdin)" )"
                cd "$prev_pwd"
            fi
        fi
        if [ -z "$CI_BASECOMMIT_HASH" ]; then
            set -$options
            if [ -n "$CHANGE_TARGET" ]; then
                refs="refs/heads/$CHANGE_TARGET"
            elif [ -n "$GITHUB_BASE_REF" ]; then
                refs="refs/heads/$GITHUB_BASE_REF"
            else
                refs="refs/heads/master" # should not happen
            fi
            export GITHUB_BASECOMMIT_HASH="$(git ls-remote https://github.com/${GITHUB_REPOSITORY}.git | grep -m1 "${refs}\$" | grep -v "refs/original" | cut -f 1)"
        fi
    # elif [ -n "$GIT_COMMIT" ]; then # This seems BROKEN since GIT_COMMIT is often wrong
        # export GITHUB_COMMIT_HASH="$GIT_COMMIT"
    else
        if [[ "$branch" == "origin/"* ]]; then
            local branch_name="${branch#*/}"
            refs="refs/heads/$branch_name"
        elif [[ "$branch" == *"/PR-"* ]]; then
            local pr_id="${branch#*-}"
            refs="refs/pull/$pr_id/head"
        else
            refs="$branch" # should not happen
        fi
        if [ -z "$GITHUB_COMMIT_HASH" ]; then
            export GITHUB_COMMIT_HASH="$(git ls-remote https://github.com/${GITHUB_REPOSITORY}.git | grep -m1 "${refs}\$" | grep -v "refs/original" | cut -f 1)"
        fi
        # export GITHUB_COMMIT_HASH="$(git log -n 1 $branch --pretty=format:"%H")"
        # echo "Trying to guess GITHUB_COMMIT_HASH: $GITHUB_COMMIT_HASH"
    fi
    
    if [ -n "$CI_DEBUG" ]; then
        echo "Debug info for GitHub env vars export:"
        echo "  python_exe = $python_exe"
        echo "  git_url = $git_url"
        echo "  refs = $refs"
        echo "  branch = $branch"
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
            export GITHUB_COMMIT_MESSAGE="$( echo "$response" | $python_exe -c "import sys,githubJsonParser; githubJsonParser.get_commit_message(sys.stdin)" )"
            export GITHUB_COMMIT_AUTHOR="$( echo "$response" | $python_exe -c "import sys,githubJsonParser; githubJsonParser.get_commit_author(sys.stdin)" )"
            export GITHUB_COMMIT_DATE="$( echo "$response" | $python_exe -c "import sys,githubJsonParser; githubJsonParser.get_commit_date(sys.stdin)" )"
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

github-get-pr-latest-build-comment() {
    local pr_id="$1"
    local python_exe="python"
    if [ ! -x "$(command -v "$python_exe")" ]; then
        if [ -n "$VM_PYTHON_PATH" ] && [ -e "$(cd $VM_PYTHON_PATH && pwd)/python.exe" ]; then
            python_exe="$(cd $VM_PYTHON_PATH && pwd)/python.exe"
        else
            echo "ERROR: Python executable not found. Try setting VM_PYTHON_PATH variable."
        fi
    fi
    local options="$-"
    set +x # Private stuff here: echo disabled
    if [ -n "$GITHUB_SOFABOT_TOKEN" ] &&
       [ -n "$GITHUB_REPOSITORY" ]; then
        response="$(curl --silent --header "Authorization: token $GITHUB_SOFABOT_TOKEN" "https://api.github.com/repos/$GITHUB_REPOSITORY/issues/$pr_id/comments")"
        if [ -n "$response" ]; then
            local prev_pwd="$(pwd)"
            cd "$SCRIPT_DIR"
            latest_build_comment="$( echo "$response" | $python_exe -c "import sys,githubJsonParser; githubJsonParser.get_latest_build_comment(sys.stdin)" )"
            cd "$prev_pwd"
        fi
    fi
    set -$options
    echo "$latest_build_comment"
}

github-get-pr-diff() {
    local pr_id="$1"
    local options="$-"
    set +x # Private stuff here: echo disabled
    if [ -n "$GITHUB_SOFABOT_TOKEN" ] &&
       [ -n "$GITHUB_REPOSITORY" ]; then
        response="$(curl -L --silent --header "Authorization: token $GITHUB_SOFABOT_TOKEN" "https://github.com/$GITHUB_REPOSITORY/pull/${pr_id}.diff")"
    fi
    set -$options
    echo "$response"
}

github-get-pr-state() {
    local pr_id="$1"
    local python_exe="python"
    if [ ! -x "$(command -v "$python_exe")" ]; then
        if [ -n "$VM_PYTHON_PATH" ] && [ -e "$(cd $VM_PYTHON_PATH && pwd)/python.exe" ]; then
            python_exe="$(cd $VM_PYTHON_PATH && pwd)/python.exe"
        else
            echo "ERROR: Python executable not found. Try setting VM_PYTHON_PATH variable."
        fi
    fi
    if [ -z "$GITHUB_REPOSITORY" ]; then
        export GITHUB_REPOSITORY="sofa-framework/sofa"
    fi
    local options="$-"
    set +x # Private stuff here: echo disabled
    if [ -n "$GITHUB_SOFABOT_TOKEN" ] &&
       [ -n "$GITHUB_REPOSITORY" ]; then
        response="$(curl --silent --header "Authorization: token $GITHUB_SOFABOT_TOKEN" "https://api.github.com/repos/$GITHUB_REPOSITORY/pulls/$pr_id")"
        if [ -n "$response" ]; then
            local prev_pwd="$(pwd)"
            cd "$SCRIPT_DIR"
            state="$( echo "$response" | $python_exe -c "import sys,githubJsonParser; githubJsonParser.get_state(sys.stdin)" )"
            cd "$prev_pwd"
        fi
    fi
    set -$options
    echo "$state"
}

