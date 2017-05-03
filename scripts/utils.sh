#!/bin/bash
set -o errexit # Exit on error

vm-is-windows() {
    if [[ "$(uname)" != "Darwin" && "$(uname)" != "Linux" ]]; then
        return 0 # true
    else
        return 1 # false
    fi
}

get-msvc-year() {
    if vm-is-windows; then 
        case $1
            "VS-2012") echo "2012" ;;
            "VS-2013") echo "2013" ;;
            "VS-2015") echo "2015" ;;
            "VS-2017") echo "2017" ;;
        esac
    fi
}

get-msvc-version() {
    if vm-is-windows; then    
        case $1
            "VS-2012") echo "11.0" ;;
            "VS-2013") echo "12.0" ;;
            "VS-2015") echo "14.0" ;;
            "VS-2017") echo "14.1" ;;
        esac
    fi
}

get-msvc-comntools() {
    if vm-is-windows; then    
        case $1
            "VS-2012") echo "VS110COMNTOOLS" ;;
            "VS-2013") echo "VS120COMNTOOLS" ;;
            "VS-2015") echo "VS140COMNTOOLS" ;;
            "VS-2017") echo "VS141COMNTOOLS" ;;
        esac
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

list-build-options() {
    build_options=""
    if [[ "$1" == "options" ]] || [[ "$CI_PLUGINS" == "options" ]]; then
        build_options="build-all-plugins $build_options"
    fi
    if [[ "$2" == "true" ]] || [[ "$CI_REPORT_TO_DASHBOARD" == "true" ]]; then
        build_options="report-to-dashboard $build_options"
    fi
    if [[ "$3" == "true" ]] || [[ "$CI_REPORT_TO_GITHUB" == "true" ]]; then
        build_options="report-to-github $build_options"
    fi
    if [[ "$4" == "true" ]] || [[ "$CI_FORCE_FULL_BUILD" == "true" ]]; then
        build_options="force-full-build $build_options"
    fi
    if [[ "$5" == "true" ]] || [[ "$CI_RUN_UNIT_TESTS" == "true" ]]; then
        build_options="run-unit-tests $build_options"
    fi
    if [[ "$6" == "true" ]] || [[ "$CI_RUN_SCENE_TESTS" == "true" ]]; then
        build_options="run-scene-tests $build_options"
    fi
    echo "$build_options"
}