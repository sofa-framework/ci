#!/bin/bash

notify-dashboard() {
    if [ -z "$CI_DASHBOARD_URL" ]; then
        echo "Message (not sent): " sha="$sha" "config=$CI_JOB" $*
        true
    else
        local message="$1"
        while [ $# -gt 1 ]; do
            shift
            message="$message&$1"
        done
        message="$message&sha=$sha&config=$CI_JOB"
        local url="$CI_DASHBOARD_URL"
        echo "Message (sent): " sha="$sha" "config=$CI_JOB" $*
        wget --no-verbose --output-document=/dev/null --post-data="$message" "$CI_DASHBOARD_URL"
    fi
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