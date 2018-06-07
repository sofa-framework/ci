#!/bin/bash
set -o errexit # Exit on error

usage() {
    echo "Usage: pre-builds.sh <matrix-configs-string> <build-options>"
}

if [ "$#" -ge 1 ]; then
    script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
    . "$script_dir"/utils.sh

    matrix_configs_string="$1"
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


if [[ "$BUILD_CAUSE_GITHUBPULLREQUESTCOMMENTCAUSE" == "true" ]] && [[ "$GIT_BRANCH" == *"/PR-"* ]]; then
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

# WARNING: Matrix configs string must be explicit using only '()' and/or '==' and/or '&&' and/or '||'
# Example: (CI_CONFIG=='ubuntu_gcc-5.4' && CI_PLUGINS=='options' && CI_TYPE=='release') || (CI_CONFIG=='windows7_VS-2015_amd64' && CI_PLUGINS=='options' && CI_TYPE=='release')
IFS='||' read -ra matrix_configs <<< "$matrix_configs_string"
for matrix_config in "${matrix_configs[@]}"; do
    if [[ "$matrix_config" != *"=="* ]]; then
        continue
    fi

    # WARNING: Matrix Axis names may change (Jenkins)
    config="$(echo "$matrix_config" | sed "s/.*CI_CONFIG *== *'\([^']*\)'.*/\1/g" )"
    platform="$(get-platform-from-config "$config")"
    compiler="$(get-compiler-from-config "$config")"
    architecture="$(get-architecture-from-config "$config")"
    build_type="$(echo "$matrix_config" | sed "s/.*CI_TYPE *== *'\([^']*\)'.*/\1/g" )"
    plugins="$(echo "$matrix_config" | sed "s/.*CI_PLUGINS *== *'\([^']*\)'.*/\1/g" )"

    # Update DASH_CONFIG and GITHUB_CONTEXT upon matrix_config parsing
    build_options="$(get-build-options "$plugins")"
    export DASH_CONFIG="$(dashboard-config-string "$platform" "$compiler" "$architecture" "$build_type" "$build_options")"
    export GITHUB_CONTEXT="$DASH_CONFIG"

    # Notify GitHub and Dashboard
    github-notify "pending" "Build queued."
    dashboard-notify "status="

    sleep 1 # ensure we are not flooding APIs
done

