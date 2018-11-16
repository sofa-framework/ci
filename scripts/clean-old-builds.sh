#!/bin/bash
set -o errexit # Exit on error

usage() {
    echo "Usage: clean-old-builds.sh <base-dir>"
}

if [ "$#" -eq 1 ]; then
    SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
    . "$SCRIPT_DIR"/utils.sh
    . "$SCRIPT_DIR"/github.sh
    
    BASE_DIR="$(cd "$1" && pwd)"
else
    usage; exit 1
fi

load-vm-env

cd "$BASE_DIR"

for dir in *; do
    if [ ! -d "$dir" ]; then
        break
    fi
    
    status="not removed"
    
    echo "$dir:"
    if [[ "$dir" == "PR-"* ]]; then # PR dir
        # check if this PR is closed
        pr_id="${dir#*-}"
        pr_state="$(github-get-pr-state "$pr_id")"
        if [[ "$pr_state" == "closed" ]]; then
            echo "  PR $pr_id is closed"
            status="removed"
        fi
    fi
    if [[ "$dir" != "master" ]]; then # branch or PR dir except master
        cd "$dir"
        for config in *; do
            if [ ! -d "$config" ] || [[ "$config" == *"tmp" ]] || [ ! -d "$config/src/SofaKernel" ]; then
                break
            fi
            if [ -d "$config/build" ]; then
                # check last build date
                now_epoch="$(date +%s)"
                if vm-is-macos; then
                    lastedit_epoch="$(stat -f "%m" $config/build)"
                else
                    lastedit_epoch="$(date +%s -r $config/build)"
                fi
                delta=$(( now_epoch - lastedit_epoch )) # in seconds
                echo "  last build on $config was $delta seconds ago"
                if [ "$delta" -gt 1209600 ]; then # 3600*24*14 = 14 days
                    status="removed"
                else
                    # remove only if ALL configs are old
                    status="not removed"
                    break
                fi
            else
                status="removed"
            fi
        done
        cd ..
    fi
    
    if [[ "$status" == "removed" ]]; then
        rm -rf "$dir"
    fi
    echo "  -> $status"
done


