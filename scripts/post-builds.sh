#!/bin/bash
set -o errexit # Exit on error

usage() {
    echo "Usage: post-builds.sh <matrix-combinations-string> <output-dir> <build-options>"
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

. "$script_dir"/dashboard.sh
. "$script_dir"/github.sh

# github-export-vars "$build_options"
# dashboard-export-vars "$build_options"
load-env-vars "GITHUB" "$output_dir" # Retrieve GITHUB env vars
load-env-vars "DASH" "$output_dir" # Retrieve DASH env vars

if [[ "$DASH_COMMIT_BRANCH" == *"/PR-"* ]]; then
    # Get info about this PR from GitHub API
    pr_id="${DASH_COMMIT_BRANCH#*-}"
    pr_latest_build_comment="$(github-get-pr-latest-build-comment "$pr_id")"
    # pr_json="$(github-get-pr-json "$pr_id")"
    # pr_diff="$(github-get-pr-diff "$pr_id")"
    #
    # pr_description="$(github-get-pr-description "$pr_json")"
    # pr_labels="$(github-get-pr-labels "$pr_json")"

    if [[ "$pr_latest_build_comment" == *"[generate-binaries]"* ]]; then
        echo "[generate-binaries] detected: sending github comment with artifacts info."
        github_comment_header='**[generate-binaries]** detected during [build #'$BUILD_NUMBER']('$BUILD_URL').'
        github_comment_body='\n\nHere are your binaries:'
        artifacts_detected="false"

        # WARNING: Matrix combinations string must be explicit using only '()' and/or '==' and/or '&&' and/or '||'
        # Example: (CI_CONFIG=='ubuntu_gcc-5.4' && CI_PLUGINS=='options' && CI_TYPE=='release') || (CI_CONFIG=='windows7_VS-2015_amd64' && CI_PLUGINS=='options' && CI_TYPE=='release')
        IFS='||' read -ra matrix_combinations <<< "$matrix_combinations_string"
        for matrix_combination in "${matrix_combinations[@]}"; do
            if [[ "$matrix_combination" != *"=="* ]]; then
                continue
            fi

            # WARNING: Matrix Axis names may change (Jenkins)
            config="$(echo "$matrix_combination" | sed "s/.*CI_CONFIG *== *'\([^']*\)'.*/\1/g" )"
            build_type="$(echo "$matrix_combination" | sed "s/.*CI_TYPE *== *'\([^']*\)'.*/\1/g" )"
            plugins="$(echo "$matrix_combination" | sed "s/.*CI_PLUGINS *== *'\([^']*\)'.*/\1/g" )"

            # e.g. https://ci.inria.fr/sofa-ci-dev/job/sofa-framework/job/PR-2740/7/CI_CONFIG=ubuntu_gcc,CI_PLUGINS=options,CI_TYPE=release/artifact/parent_dir/build/SOFA_*.zip
            build_url_no_trailing="$(echo "$BUILD_URL" | sed 's:/*$::')"
            artifact_url="$build_url_no_trailing/CI_CONFIG=$config,CI_PLUGINS=$plugins,CI_TYPE=$build_type/artifact/parent_dir/build/SOFA_*.zip"
            if curl --output /dev/null --silent --head --fail "$artifact_url"; then
                echo "URL exists: $artifact_url"
                artifacts_detected="true"
                github_comment_body=$github_comment_body'\n  - ['$config'_'$plugins']('$artifact_url')'
            else
                echo "URL does not exist: $artifact_url"
            fi

            sleep 1 # ensure we are not flooding APIs
        done

        if [[ "$artifacts_detected" == "true" ]]; then
            # github-post-pr-comment "$pr_id" "$github_comment_header $github_comment_body"
            echo "GitHub comment:"
            echo "$github_comment_header $github_comment_body"
        fi
    fi
fi
