#!/bin/bash

notify-dashboard() {
    # hash=$(git log --pretty=format:'%H' -1)
    # if [ -z "$CI_DASHBOARD_URL" ]; then
        # echo "Message (not sent): " sha="$hash" "config=$CI_JOB" $*
        # true
    # else
        # local message="$1"
        # while [ $# -gt 1 ]; do
            # shift
            # message="$message&$1"
        # done
        # message="$message&sha=$hash&config=$CI_JOB"
        # local url="$CI_DASHBOARD_URL"
        # echo "Message (sent): " sha="$hash" "config=$CI_JOB" $*
        # wget --no-verbose --output-document=/dev/null --post-data="$message" "$CI_DASHBOARD_URL"
    # fi
    echo "notify dashboard $*"
}

count-warnings() {
    local warning_count=-1
    if [[ $(uname) = Darwin || $(uname) = Linux ]]; then
        warning_count=$(grep '^[^:]\+:[0-9]\+:[0-9]\+: warning:' "$build_dir/make-output.txt" | sort -u | wc -l | tr -d ' ')
    else
        warning_count=$(grep ' : warning [A-Z]\+[0-9]\+:' "$build_dir/make-output.txt" | sort | uniq | wc -l)
    fi
    echo "$warning_count"
}

vm-is-windows() {
    if [[ "$(uname)" != "Darwin" && "$(uname)" != "Linux" ]]; then
        return 0 # true
    else
        return 1 # false
    fi
}

in-array() {
    IFS=' ' read -ra array <<< "$2"
    for e in "${array[@]}"; do   
        if [[ "$e" == "$1" ]]; then
            return 0; 
        fi
    done
    return 1
}
