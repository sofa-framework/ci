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

echo "$GITHUB_COMMIT_HASH" > "$output_dir/github_commit_hash.txt"
echo "$GITHUB_BASECOMMIT_HASH" > "$output_dir/github_basecommit_hash.txt"

# Check [ci-ignore] flag in commit message
if [ -n "$GITHUB_COMMIT_MESSAGE" ] && [[ "$GITHUB_COMMIT_MESSAGE" == *"[ci-ignore]"* ]]; then
    # Ignore this build
    touch "abort-this-build"
    echo "WARNING: [ci-ignore] detected in commit message, build aborted."
    exit 1
fi


dashboard-init

# Set Dashboard line on GitHub
GITHUB_CONTEXT_OLD="$GITHUB_CONTEXT"
GITHUB_TARGET_URL_OLD="$GITHUB_TARGET_URL"
export GITHUB_CONTEXT="Dashboard"
export GITHUB_TARGET_URL="https://www.sofa-framework.org/dash?branch=$DASH_COMMIT_BRANCH"
github-notify "success" "Builds triggered."
export GITHUB_CONTEXT="$GITHUB_CONTEXT_OLD"
export GITHUB_TARGET_URL="$GITHUB_TARGET_URL_OLD"


if [[ "$DASH_COMMIT_BRANCH" == *"/PR-"* ]]; then
    # Get latest [ci-build] comment in PR
    pr_id="${DASH_COMMIT_BRANCH#*-}"
    latest_build_comment="$(github-get-pr-latest-build-comment "$pr_id")"
    
    GITHUB_CONTEXT_OLD="$GITHUB_CONTEXT"
    export GITHUB_CONTEXT="[with-scene-tests]"
    
    if [[ "$latest_build_comment" == *"[with-scene-tests]"* ]] || 
       [[ "$latest_build_comment" == *"[with-all-tests]"* ]]; then
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
    
    export GITHUB_CONTEXT="[with-regression-tests]"
    
    if [[ "$latest_build_comment" == *"[with-regression-tests]"* ]] || 
       [[ "$latest_build_comment" == *"[with-all-tests]"* ]]; then
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
    
    if [[ "$latest_build_comment" == *"[force-full-build]"* ]]; then
        echo "Full build: forced."
        echo "true" > "$output_dir/force-full-build" # will be searched by Groovy script on launcher to set CI_FORCE_FULL_BUILD
    fi
    
    export GITHUB_CONTEXT="$GITHUB_CONTEXT_OLD"
elif [[ "$DASH_COMMIT_BRANCH" == "origin/master" ]]; then
    # Always scene tests for master builds
    echo "true" > "$output_dir/enable-scene-tests" # will be searched by Groovy script on launcher to set CI_RUN_SCENE_TESTS    
    # Always regression tests for master builds
    echo "true" > "$output_dir/enable-regression-tests" # will be searched by Groovy script on launcher to set CI_RUN_REGRESSION_TESTS
fi

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

