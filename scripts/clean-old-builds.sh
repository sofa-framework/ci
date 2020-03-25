#!/bin/bash
set -o errexit # Exit on error

usage() {
    echo "Usage: clean-old-builds.sh <base-dir>"
}

last-edit() {
    check_dir="$1"
    mode="$2"

    # check last build date
    now_epoch="$(date +%s)"
    if vm-is-macos; then
        lastedit_date="$(stat -f "%Sm" $check_dir)"
        lastedit_epoch="$(stat -f "%m" $check_dir)"
    else
        lastedit_date="$(date -r $check_dir)"
        lastedit_epoch="$(date +%s -r $check_dir)"
    fi

    check_delta=$(( now_epoch - lastedit_epoch )) # in seconds

    if [[ "$mode" == "date" ]]; then
        echo "$lastedit_date"
    elif [[ "$mode" == "seconds" ]]; then
        echo "$check_delta"
    fi
}

if [ "$#" -eq 1 ]; then
    SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
    . "$SCRIPT_DIR"/utils.sh
    . "$SCRIPT_DIR"/github.sh

    BASE_DIR="$(cd "$1" && pwd)"
    MAX_DAYS_SINCE_MODIFIED=10 # = 3600*24*10 = 10 days
    max_sec_since_modified=$(( 3600 * 24 * $MAX_DAYS_SINCE_MODIFIED ))
else
    usage; exit 1
fi

load-vm-env

cd "$BASE_DIR"

for dir in *; do
    if [ ! -d "$dir" ]; then
        continue
    fi

    echo "$dir:"

    if [[ "$dir" == "PR-"* ]]; then # PR dir
        # check if this PR is closed
        pr_id="${dir#*-}"
        pr_state="$(github-get-pr-state "$pr_id")"
        if [[ "$pr_state" == "closed" ]]; then
            echo "  PR $pr_id is closed"
            echo "  -> removed"
            rm -rf "$dir"
            continue
        fi
    fi

    if [[ "$BASE_DIR" == *"/launcher/"* ]]; then
        # Launcher has no config/build, only sources
        echo "Launcher detected."
        delta="$(last-edit "$dir" "seconds")"
        lastedit_date="$(last-edit "$dir" "date")"
        echo -n "  last launch: $lastedit_date"
        if [ "$delta" -gt $max_sec_since_modified ]; then
            echo " (more than $MAX_DAYS_SINCE_MODIFIED days ago)"
            echo "  -> removed"
            rm -rf "$dir"
        else
            echo "" # newline
            echo "  -> not removed"
        fi
    else
        cd "$dir"
        all_configs_removed="true"
        for config in *; do
            if [ ! -d "$config" ] || [[ "$config" == *"tmp" ]] || [ ! -d "$config/src/SofaKernel" ]; then
                continue
            fi
            echo "  $config:"
            if [ -d "$config/build" ]; then
                delta="$(last-edit "$config/build" "seconds")"
                lastedit_date="$(last-edit "$config/build" "date")"
                echo -n "    last build was on $lastedit_date"
                if [ "$delta" -gt $max_sec_since_modified ]; then
                    echo " (more than $MAX_DAYS_SINCE_MODIFIED days ago)"
                    echo "    -> removed"
                    rm -rf "$config"
                else
                    echo "" # newline
                    echo "    -> not removed"
                    all_configs_removed="false"
                fi
            else
                echo "  $config: no build dir"
            fi
        done
        cd ..
        if [[ "$all_configs_removed" == "true" ]]; then
            echo "  All valid configs were removed"
            echo "  -> $dir removed"
            rm -rf "$dir"
        fi
    fi
done

# Clean Docker
if [ -x "$(command -v docker)" ]; then
    echo ""
    echo "Cleaning Docker containers and images..."
    docker container prune --force || true
    docker image prune --force || true
fi


