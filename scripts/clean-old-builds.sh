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
    
    if [[ "$dir" == "PR-"* ]]; then # PR dir
        # check if this PR is closed
        pr_id="${dir#*-}"
        pr_state="$(github-get-pr-state "$pr_id")"
        if [[ "$pr_state" == "closed" ]]; then
            status="removed"
        fi
    elif [ -d "SofaKernel" ] && [[ "$dir" != "master" ]]; then # branch dir (except master)
        cd "$dir"
        for config in *; do
            if [ ! -d "$config" ] || [[ "$config" == *"tmp" ]]; then
                break
            fi
            if [ -d "$config/build" ]; then
                # check last build date
                now_epoch="$(date +%s)"
                lastedit_epoch="$(date +%s -r $config/build)"
                delta=$(( now_epoch - lastedit_epoch )) # in seconds
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
    echo "$dir: $status"
done


