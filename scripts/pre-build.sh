#!/bin/bash
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
. "$SCRIPT_DIR"/dashboard.sh
. "$SCRIPT_DIR"/github.sh

usage() {
    echo "Usage: pre-build.sh <configs-string> <build-options>"
}

if [ "$#" -ge 1 ]; then
    configs_string="$1"
    build_options="${*:2}"
    if [ -z "$build_options" ]; then
        build_options="$(import-build-options)" # use env vars (Jenkins)
    fi
else
    usage; exit 1
fi

IFS='||' read -ra configs <<< "$configs_string"
for config in "${configs[@]}"; do
    # echo "config = $config"
    if [[ "$config" != *"=="* ]]; then
        continue
    fi

    # WARNING: Jenkins parameter names may change
    compiler="$(echo "$config" | sed "s/.*CI_COMPILER *== *'\([^']*\)'.*/\1/g" )"
    architecture="$(echo "$config" | sed "s/.*CI_ARCH *== *'\([^']*\)'.*/\1/g" )"
    build_type="$(echo "$config" | sed "s/.*CI_TYPE *== *'\([^']*\)'.*/\1/g" )"

    dashboard-export-vars "${compiler#*_}" "$architecture" "$build_type" "$build_options"
    dashboard-init

    github-export-vars "$build_options"
    github-notify "Build queued."

    sleep 1 # ensure we are not flooding APIs
done
