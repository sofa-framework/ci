#!/bin/bash
set -o errexit # Exit on error

vm-is-macos() {
    if [[ "$(uname)" == "Darwin" ]]; then
        return 0 # true
    else
        return 1 # false
    fi
}
vm-is-windows() {
    if [[ "$(uname)" != "Darwin" && "$(uname)" != "Linux" ]]; then
        return 0 # true
    else
        return 1 # false
    fi
}
vm-is-centos() {
    if [[ "$(uname)" != "Darwin" && "$(uname)" == "Linux" ]] && [ -x "$(command -v yum)" ]; then
        return 0 # true
    else
        return 1 # false
    fi
}
vm-is-ubuntu() {
    if [[ "$(uname)" != "Darwin" && "$(uname)" == "Linux" ]] && [ -x "$(command -v apt)" ]; then
        return 0 # true
    else
        return 1 # false
    fi
}

package-is-installed() {
    dpkg -l "$1" > /dev/null 2>&1
    return $?
}

get-msvc-year() {
    if vm-is-windows; then
        local compiler="$(echo "$1" | tr '[:upper:]' '[:lower:]')"
        case "$compiler" in
            vs-2012) echo "2012" ;;
            vs-2013) echo "2013" ;;
            vs-2015) echo "2015" ;;
            vs-2017) echo "2017" ;;
        esac
    fi
}

get-compiler-version() {
    local compiler="$(echo "$1" | tr '[:upper:]' '[:lower:]')"
    case "$compiler" in
        vs-2012) echo "11.0" ;;
        vs-2013) echo "12.0" ;;
        vs-2015) echo "14.0" ;;
        vs-2017) echo "14.1" ;;
        gcc-*)   echo "${compiler#*-}" ;;
        clang-*) echo "${compiler#*-}" ;;
    esac
}

get-msvc-comntools() {
    if vm-is-windows; then
        local compiler="$(echo "$1" | tr '[:upper:]' '[:lower:]')"
        case "$compiler" in
            vs-2012) echo "VS110COMNTOOLS" ;;
            vs-2013) echo "VS120COMNTOOLS" ;;
            vs-2015) echo "VS140COMNTOOLS" ;;
            vs-2017) echo "VS141COMNTOOLS" ;;
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

get-build-options() {
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