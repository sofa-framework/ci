#!/bin/bash
set -o errexit # Exit on error

usage() {
    echo "Usage: pre-builds.sh <configs-string> <build-options>"
}

if [ "$#" -ge 1 ]; then
    script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
    . "$script_dir"/utils.sh

    configs_string="$1"
    build_options="${*:2}"
    if [ -z "$build_options" ]; then
        build_options="$(get-build-options)" # use env vars (Jenkins)
    fi
else
    usage; exit 1
fi

. "$script_dir"/dashboard.sh
. "$script_dir"/github.sh

github-export-vars "$build_options"
dashboard-export-vars "$build_options"
dashboard-init

IFS='||' read -ra configs <<< "$configs_string"
for config in "${configs[@]}"; do
    if [[ "$config" != *"=="* ]]; then
        continue
    fi

    # WARNING: Matrix Axis names may change (Jenkins)
    platform_compiler="$(echo "$config" | sed "s/.*CI_COMPILER *== *'\([^']*\)'.*/\1/g" )"
    platform="${platform_compiler%_*}" # ubuntu_gcc-4.8 -> ubuntu
    compiler="${platform_compiler#*_}" # ubuntu_gcc-4.8 -> gcc-4.8
    architecture="$(echo "$config" | sed "s/.*CI_ARCH *== *'\([^']*\)'.*/\1/g" )"
    build_type="$(echo "$config" | sed "s/.*CI_TYPE *== *'\([^']*\)'.*/\1/g" )"
    plugins="$(echo "$config" | sed "s/.*CI_PLUGINS *== *'\([^']*\)'.*/\1/g" )"

    # Update DASH_CONFIG and GITHUB_CONTEXT upon config parsing
    build_options="$(get-build-options "$plugins")"
    export DASH_CONFIG="$(dashboard-config-string "$platform" "$compiler" "$architecture" "$build_type" "$build_options")"
    export GITHUB_CONTEXT="$DASH_CONFIG"

    # Notify GitHub and Dashboard
    github-notify "pending" "Build queued."
    dashboard-notify "status="

    sleep 1 # ensure we are not flooding APIs
done


if [[ "$BUILD_CAUSE_GITHUBPULLREQUESTCOMMENTCAUSE" == "true" ]] && [[ "$GIT_BRANCH" == "PR-"* ]]; then
    # Get latest [ci-build] comment in PR
    pr_id="${GIT_BRANCH#*-}"
    latest_build_comment="$(github-get-latest-build-comment "$pr_id")"
    if [[ "$latest_build_comment" == *"[with-scene-tests]"* ]]; then
        touch "$WORKSPACE/enable-scene-tests"
    else
        echo "[with-scene-tests] NOT detected"
        # compute diff size
        # if big diff: scene tests should be triggered
        # else: scene tests ignored
    fi
fi

