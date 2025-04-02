#!/bin/bash
set -o errexit # Exit on error

usage() {
    echo "Usage: pre-builds.sh <matrix-combinations-string> <output-dir> <build-options>"
}

if [ "$#" -ge 2 ]; then
    script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
    . "$script_dir"/utils.sh

    matrix_combinations_string="$1"

    if [ ! -d "$2" ]; then
        mkdir -p "$2";
    fi
    output_dir="$( cd "$2" && pwd )"

    build_options="${*:3}"
    if [ -z "$build_options" ]; then
        build_options="$(get-build-options)" # use env vars (Jenkins)
    fi
else
    usage; exit 1
fi

rm -rf "$output_dir/*"

. "$script_dir"/dashboard.sh
. "$script_dir"/github.sh

github-export-vars "$build_options"
dashboard-export-vars "$build_options"
save-env-vars "GITHUB" "$output_dir"
save-env-vars "DASH" "$output_dir"

echo "$GITHUB_COMMIT_HASH" > "$output_dir/GITHUB_COMMIT_HASH.txt"
echo "$GITHUB_BASECOMMIT_HASH" > "$output_dir/GITHUB_BASECOMMIT_HASH.txt"


if [[ "$DASH_COMMIT_BRANCH" == *"/PR-"* ]]; then

    # Get info about this PR from GitHub API
    pr_id="${DASH_COMMIT_BRANCH#*-}"
    pr_json="$(github-get-pr-json "$pr_id")"
    pr_latest_build_comment="$(github-get-pr-latest-build-comment "$pr_id")"
    pr_diff="$(github-get-pr-diff "$pr_id")"

    pr_description="$(github-get-pr-description "$pr_json")"
    pr_labels="$(github-get-pr-labels "$pr_json")"

    echo "----------- [ci-depends-on] -----------"
    GITHUB_CONTEXT_RESET="$GITHUB_CONTEXT" # save
    export GITHUB_CONTEXT="[ci-depends-on]" # edit
    pr_has_dependencies="false"
    pr_is_mergeable="true"
    github_comment_header='**[ci-depends-on]** detected during [build #'$BUILD_NUMBER']('$BUILD_URL').'
    github_comment_body='\n\n To unlock the merge button, you must'

    while read dependency; do
        dependency="${dependency%$'\r'}" # remove \r from dependency
        dependency_url="$(echo "$dependency" | sed 's:\[ci-depends-on \(.*\)\]:\1:g')"
        echo "dependency_url = $dependency_url"
        if ! curl -sSf "$dependency_url" > /dev/null; then
            # bad url
            continue
        fi

        pr_has_dependencies="true"
        dependency_json="$(github-get-pr-json "$dependency_url")"
        dependency_state="$(github-get-pr-state "$dependency_json")"
        dependency_is_merged="$(github-is-pr-merged "$dependency_json")"
        dependency_project_name="$(github-get-pr-project-name "$dependency_json")"
        dependency_project_url="$(github-get-pr-project-url "$dependency_json")"
        dependency_merge_commit="$(github-get-pr-merge-commit "$dependency_json")"
        dependency_merge_branch="$(github-get-pr-merge-branch "$dependency_json")"

        echo "dependency_state = $dependency_state"
        echo "dependency_is_merged = $dependency_is_merged"
        echo "dependency_project_name = $dependency_project_name"
        echo "dependency_project_url = $dependency_project_url"
        echo "dependency_merge_commit = $dependency_merge_commit"
        echo "dependency_merge_branch = $dependency_merge_branch"

        fixed_name=$(echo "$dependency_project_name" |  awk '{gsub(/\./, "_"); print toupper($0)}')
        flag_repository="-D${fixed_name}_GIT_REPOSITORY='$dependency_project_url'"
        flag_tag="-D${fixed_name}_GIT_TAG='$dependency_merge_commit'"

        if [[ "$dependency_is_merged" != [Tt]"rue" ]]; then # this dependency is a merged PR
            github_comment_body=$github_comment_body'\n- **Merge or close '$dependency_url'**\n_For this build, the following CMake flags will be set_\n'${flag_repository}'\n'${flag_tag}
            pr_is_mergeable="false"
        fi
    done < <( echo "$pr_description" | grep '\[ci-depends-on' )

    if [[ "$pr_has_dependencies" == "true" ]]; then
        if [[ "$pr_is_mergeable" == "true" ]]; then
            # PR has dependencies that are all closed/merged and ExternalProject pointers are up-to-date
            github_comment_body='\n\n All dependencies are merged/closed. Congrats! :+1:'
            github-notify "success" "Dependencies are OK."
            github-post-pr-comment "$pr_id" "$github_comment_header $github_comment_body"
        else
            github-notify "failure" "Please follow instructions in comments."
            github-post-pr-comment "$pr_id" "$github_comment_header $github_comment_body"
        fi
    else
        github-notify "success" "No dependency found in description."
    fi
    export GITHUB_CONTEXT="$GITHUB_CONTEXT_RESET" # reset
    echo "---------------------------------------"

    # If build was triggered automatically
    if [[ "$BUILD_CAUSE" == *"BRANCHEVENTCAUSE"* ]]; then
        # Check [ci-ignore] flag in commit message
        if [[ "$GITHUB_COMMIT_MESSAGE" == *"[ci-ignore]"* ]]; then
            # Ignore this build
            echo "WARNING: [ci-ignore] detected in commit message, build ignored."
            echo "true" > "$output_dir/skip-this-build" # will be searched by Groovy script on launcher
            exit 0
        fi

        # Check PR labels, search for "WIP"
        for label in "$pr_labels"; do
            if [[ "$label" == *"pr: status wip"* ]]; then
                echo "WARNING: WIP label detected, build ignored."
                echo "true" > "$output_dir/skip-this-build" # will be searched by Groovy script on launcher
                export GITHUB_CONTEXT="Dashboard"
                export GITHUB_TARGET_URL="https://www.sofa-framework.org/dash?branch=$DASH_COMMIT_BRANCH"
                github-notify "failure" "WIP label detected. Build ignored."
                exit 0
            fi
        done
    fi

    GITHUB_CONTEXT_RESET="$GITHUB_CONTEXT" # save
    export GITHUB_CONTEXT="[with-scene-tests]" # edit
    if [[ "$pr_latest_build_comment" == *"[with-scene-tests]"* ]] ||
       [[ "$pr_latest_build_comment" == *"[with-all-tests]"* ]]; then
        echo "Scene tests: forced."
        echo "true" > "$output_dir/enable-scene-tests" # will be searched by Groovy script on launcher to set CI_RUN_SCENE_TESTS
        github-notify "success" "Triggered in latest build."
    else
        echo "Scene tests: NOT forced."
        diffLineCount=999
        diffLineCount="$(github-get-pr-diff "$pr_id" | wc -l)"
        echo "Scene tests: diffLineCount = $diffLineCount"

        if [ "$diffLineCount" -lt 200 ]; then
            github-notify "success" "Ignored."
        else
            github-notify "failure" "Missing."
        fi
    fi
    export GITHUB_CONTEXT="$GITHUB_CONTEXT_RESET" # reset

    GITHUB_CONTEXT_RESET="$GITHUB_CONTEXT" # save
    export GITHUB_CONTEXT="[with-regression-tests]" # edit
    if [[ "$pr_latest_build_comment" == *"[with-regression-tests]"* ]] ||
       [[ "$pr_latest_build_comment" == *"[with-all-tests]"* ]]; then
        echo "Regression tests: forced."
        echo "true" > "$output_dir/enable-regression-tests" # will be searched by Groovy script on launcher to set CI_RUN_REGRESSION_TESTS
        github-notify "success" "Triggered in latest build."
    else
        echo "Regression tests: NOT forced."
        diffLineCount=999
        diffLineCount="$(github-get-pr-diff "$pr_id" | wc -l)"
        echo "Regression tests: diffLineCount = $diffLineCount"

        if [ "$diffLineCount" -lt 200 ]; then
            github-notify "success" "Ignored."
        else
            github-notify "failure" "Missing."
        fi
    fi
    export GITHUB_CONTEXT="$GITHUB_CONTEXT_RESET" # reset

    # If build was triggered by GitHub comment
    if [[ "$BUILD_CAUSE" == *"GITHUBPULLREQUESTCOMMENTCAUSE"* ]]; then
        if [[ "$pr_latest_build_comment" == *"[generate-binaries]"* ]]; then
            echo "[generate-binaries] detected: CI_GENERATE_BINARIES will be enabled."
            echo "true" > "$output_dir/generate-binaries" # will be searched by Groovy script on launcher to set CI_GENERATE_BINARIES
        fi

        if [[ "$pr_latest_build_comment" == *"[force-full-build]"* ]]; then
            echo "Full build: forced."
            echo "true" > "$output_dir/force-full-build" # will be searched by Groovy script on launcher to set CI_FORCE_FULL_BUILD
        fi
    fi

elif [[ "$DASH_COMMIT_BRANCH" == "origin/master" ]]; then

    # Always scene tests for master builds
    echo "true" > "$output_dir/enable-scene-tests" # will be searched by Groovy script on launcher to set CI_RUN_SCENE_TESTS
    # Always regression tests for master builds
    echo "true" > "$output_dir/enable-regression-tests" # will be searched by Groovy script on launcher to set CI_RUN_REGRESSION_TESTS

fi

# Create Dashboard line
dashboard-init

# Set Dashboard line on GitHub
GITHUB_CONTEXT_RESET="$GITHUB_CONTEXT"       # save
GITHUB_TARGET_URL_RESET="$GITHUB_TARGET_URL" # save
    export GITHUB_CONTEXT="Dashboard" # edit
    export GITHUB_TARGET_URL="https://www.sofa-framework.org/dash?branch=$DASH_COMMIT_BRANCH" # edit
    github-notify "success" "Builds triggered."
export GITHUB_CONTEXT="$GITHUB_CONTEXT_RESET"       # reset
export GITHUB_TARGET_URL="$GITHUB_TARGET_URL_RESET" # reset

# WARNING: Matrix combinations string must be explicit using only '()' and/or '==' and/or '&&' and/or '||'
# Example: (CI_CONFIG=='ubuntu_gcc-5.4' && CI_PLUGINS=='options' && CI_TYPE=='release') || (CI_CONFIG=='windows7_VS-2015_amd64' && CI_PLUGINS=='options' && CI_TYPE=='release')
IFS='||' read -ra matrix_combinations <<< "$matrix_combinations_string"
for matrix_combination in "${matrix_combinations[@]}"; do
    if [[ "$matrix_combination" != *"=="* ]]; then
        continue
    fi

    # WARNING: Matrix Axis names may change (Jenkins)
    config="$(echo "$matrix_combination" | sed "s/.*CI_CONFIG *== *'\([^']*\)'.*/\1/g" )"
    platform="$(get-platform-from-config "$config")"
    compiler="$(get-compiler-from-config "$config")"
    architecture="$(get-architecture-from-config "$config")"
    build_type="$(echo "$matrix_combination" | sed "s/.*CI_TYPE *== *'\([^']*\)'.*/\1/g" )"
    plugins="$(echo "$matrix_combination" | sed "s/.*CI_PLUGINS *== *'\([^']*\)'.*/\1/g" )"

    # Update DASH_CONFIG and GITHUB_CONTEXT upon matrix_combination parsing
    build_options="$(get-build-options "$plugins")"
    export DASH_CONFIG="$(dashboard-config-string "$platform" "$compiler" "$architecture" "$build_type" "$build_options")"
    export GITHUB_CONTEXT="$DASH_CONFIG"

    # Notify GitHub and Dashboard
    github-notify "pending" "Build queued."
    dashboard-notify "reset=true" # reset the build

    sleep 1 # ensure we are not flooding APIs
done
