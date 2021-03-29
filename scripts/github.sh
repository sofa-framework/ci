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

        response="$(curl --silent --header "Authorization: token $GITHUB_SOFABOT_TOKEN" --data "$request" "https://api.github.com/repos/$GITHUB_REPOSITORY/statuses/$GITHUB_COMMIT_HASH")"
        if [ -n "$response" ]; then
            notify="sent"
        fi
    fi
    set -$options

    echo "Notify GitHub https://api.github.com/repos/$GITHUB_REPOSITORY/statuses/$GITHUB_COMMIT_HASH ($notify): [$state] $GITHUB_CONTEXT - $message"
    #if [ -n "$response" ]; then
    #    echo "GitHub reponse: $response"
    #fi
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
                if [ -z "$GITHUB_COMMIT_HASH" ]; then
                    export GITHUB_COMMIT_HASH="$( cd "$SCRIPT_DIR" && echo "$response" | $python_exe -c "import sys,githubJsonParser; githubJsonParser.get_head_sha(sys.stdin)" )"
                fi
                export GITHUB_BASE_REF="$( cd "$SCRIPT_DIR" && echo "$response" | $python_exe -c "import sys,githubJsonParser; githubJsonParser.get_base_ref(sys.stdin)" )"
            fi
        fi
        if [ -z "$GITHUB_BASECOMMIT_HASH" ]; then
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
    fi
    echo "GITHUB_COMMIT_HASH = $GITHUB_COMMIT_HASH"
    echo "GITHUB_BASECOMMIT_HASH = $GITHUB_BASECOMMIT_HASH"
    
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
            export GITHUB_COMMIT_MESSAGE="$( cd "$SCRIPT_DIR" && echo "$response" | $python_exe -c "import sys,githubJsonParser; githubJsonParser.get_commit_message(sys.stdin)" )"
            export GITHUB_COMMIT_AUTHOR="$( cd "$SCRIPT_DIR" && echo "$response" | $python_exe -c "import sys,githubJsonParser; githubJsonParser.get_commit_author(sys.stdin)" )"
            export GITHUB_COMMIT_DATE="$( cd "$SCRIPT_DIR" && echo "$response" | $python_exe -c "import sys,githubJsonParser; githubJsonParser.get_commit_date(sys.stdin)" )"
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
    if [ -n "$CI_PYTHON_CMD" ]; then
        python_exe="$CI_PYTHON_CMD"
    fi

    local options="$-"
    set +x # Private stuff here: echo disabled
    if [ -n "$GITHUB_SOFABOT_TOKEN" ] &&
       [ -n "$GITHUB_REPOSITORY" ]; then
        response="$(curl --silent --header "Authorization: token $GITHUB_SOFABOT_TOKEN" "https://api.github.com/repos/$GITHUB_REPOSITORY/issues/$pr_id/comments")"
        if [ -n "$response" ]; then
            latest_build_comment="$( cd "$SCRIPT_DIR" && echo "$response" | $python_exe -c "import sys,githubJsonParser; githubJsonParser.get_latest_build_comment(sys.stdin)" )"
        fi
    fi
    set -$options
    echo "$latest_build_comment"
}

github-get-pr-json() {
    local pr="$1"
    local options="$-"

    if [ -z "$GITHUB_REPOSITORY" ]; then
        export GITHUB_REPOSITORY="sofa-framework/sofa"
    fi
    
    set +x # Private stuff here: echo disabled
    if [ -n "$GITHUB_SOFABOT_TOKEN" ] &&
       [ -n "$GITHUB_REPOSITORY" ]; then
        if [[ "$pr" == "{"* ]]; then
            # pr is a json string
            json="$pr"
        elif [[ "$pr" == "http"* ]]; then
            # pr is an url
            pr="$(echo "$pr" | sed 's:/github\.com/:/api.github.com/repos/:g' | sed 's:/pull/:/pulls/:g' | sed 's:/issue/:/issues/:g')"
            pr="${pr%$'\r'}"
            json="$(curl --silent --header "Authorization: token $GITHUB_SOFABOT_TOKEN" "$pr")"
        else
            # pr is an id
            json="$(curl --silent --header "Authorization: token $GITHUB_SOFABOT_TOKEN" "https://api.github.com/repos/$GITHUB_REPOSITORY/pulls/$pr")"
        fi
    fi
    set -$options
    echo "$json"
}

github-get-pr-state() {
    local python_exe="python"
    if [ -n "$CI_PYTHON_CMD" ]; then
        python_exe="$CI_PYTHON_CMD"
    fi
    
    echo "$( cd "$SCRIPT_DIR" && github-get-pr-json "$1" | $python_exe -c "import sys,githubJsonParser; githubJsonParser.get_state(sys.stdin)" )"
}

github-is-pr-merged() {
    local python_exe="python"
    if [ -n "$CI_PYTHON_CMD" ]; then
        python_exe="$CI_PYTHON_CMD"
    fi

    echo "$( cd "$SCRIPT_DIR" && github-get-pr-json "$1" | $python_exe -c "import sys,githubJsonParser; githubJsonParser.is_merged(sys.stdin)" )"
}

github-get-pr-labels() {
    local python_exe="python"
    if [ -n "$CI_PYTHON_CMD" ]; then
        python_exe="$CI_PYTHON_CMD"
    fi
    
    echo "$( cd "$SCRIPT_DIR" && github-get-pr-json "$1" | $python_exe -c "import sys,githubJsonParser; githubJsonParser.get_labels(sys.stdin)" )"
}

github-get-pr-description() {
    local python_exe="python"
    if [ -n "$CI_PYTHON_CMD" ]; then
        python_exe="$CI_PYTHON_CMD"
    fi
    
    echo "$( cd "$SCRIPT_DIR" && github-get-pr-json "$1" | $python_exe -c "import sys,githubJsonParser; githubJsonParser.get_description(sys.stdin)" )"
}

github-get-pr-project-url() {
    local python_exe="python"
    if [ -n "$CI_PYTHON_CMD" ]; then
        python_exe="$CI_PYTHON_CMD"
    fi
    
    echo "$( cd "$SCRIPT_DIR" && github-get-pr-json "$1" | $python_exe -c "import sys,githubJsonParser; githubJsonParser.get_project_url(sys.stdin)" )"
}

github-get-pr-project-name() {
    local python_exe="python"
    if [ -n "$CI_PYTHON_CMD" ]; then
        python_exe="$CI_PYTHON_CMD"
    fi
    
    echo "$( cd "$SCRIPT_DIR" && github-get-pr-json "$1" | $python_exe -c "import sys,githubJsonParser; githubJsonParser.get_project_name(sys.stdin)" )"
}

github-get-pr-merge-commit() {
    local python_exe="python"
    if [ -n "$CI_PYTHON_CMD" ]; then
        python_exe="$CI_PYTHON_CMD"
    fi
    
    echo "$( cd "$SCRIPT_DIR" && github-get-pr-json "$1" | $python_exe -c "import sys,githubJsonParser; githubJsonParser.get_merge_commit(sys.stdin)" )"
}

github-get-pr-diff() {
    local pr_id="$1"
    local python_exe="python"
    if [ -n "$CI_PYTHON_CMD" ]; then
        python_exe="$CI_PYTHON_CMD"
    fi

    if [ -z "$GITHUB_REPOSITORY" ]; then
        export GITHUB_REPOSITORY="sofa-framework/sofa"
    fi

    local options="$-"
    set +x # Private stuff here: echo disabled
    if [ -n "$GITHUB_SOFABOT_TOKEN" ] &&
       [ -n "$GITHUB_REPOSITORY" ]; then
        response="$(curl --silent --header "Authorization: token $GITHUB_SOFABOT_TOKEN" "https://patch-diff.githubusercontent.com/raw/$GITHUB_REPOSITORY/pull/${pr_id}.diff")"
        if [ -n "$response" ]; then
            diff="$response"
        fi
    fi
    set -$options
    echo "$diff"
}

github-post-pr-comment() {
    local pr_id="$1"
    local message="$2"

    local options="$-"
    local notify="not sent"
    local response=""

    set +x # Private stuff here: echo disabled
    if [[ "$GITHUB_NOTIFY" == "true" ]] &&
       [ -n "$GITHUB_REPOSITORY" ] &&
       [ -n "$GITHUB_SOFABOT_TOKEN" ]; then
        request="{\"body\": \"$message\"}"
        request="${request%$'\r'}"
        response="$(curl --silent -H "Authorization: token $GITHUB_SOFABOT_TOKEN" -X POST -d "$request" "https://api.github.com/repos/${GITHUB_REPOSITORY}/issues/${pr_id}/comments")"
        if [ -n "$response" ]; then
            notify="sent"
        fi
    fi
    set -$options

    echo "Post GitHub comment ($notify): $message"
    #if [ -n "$response" ]; then
    #    echo "GitHub reponse: $response"
    #fi
}
