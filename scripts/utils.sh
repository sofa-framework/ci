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
    if [[ "$(uname)" == "Linux" ]] && [ -x "$(command -v yum)" ]; then
        return 0 # true
    else
        return 1 # false
    fi
}
vm-is-ubuntu() {
    if [[ "$(uname)" == "Linux" ]] && [ -x "$(command -v apt)" ]; then
        return 0 # true
    else
        return 1 # false
    fi
}

load-vm-env() {
    # VM environment variables
    echo "ENV VARS: load $SCRIPT_DIR/env/default"
    . "$SCRIPT_DIR/env/default"
    if [ -n "$NODE_NAME" ]; then
        if [ -e "$SCRIPT_DIR/env/$NODE_NAME" ]; then
            echo "ENV VARS: load node specific $SCRIPT_DIR/env/$NODE_NAME"
            . "$SCRIPT_DIR/env/$NODE_NAME"
        else
            echo "ERROR: No config file found for node $NODE_NAME."
            exit 1
        fi
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

get-platform-from-config() {
    if [ "$#" -eq 1 ]; then
        config="$1"
    elif [ -n "$CI_CONFIG" ]; then
        config="$CI_CONFIG"
    fi
    
    # substitute eventually 2 times to handle "windows_vs-2015_x32" case
    subconfig="${config%_*}" # take first part
    if [[ "$subconfig" == *"_"* ]]; then
        echo "${subconfig%_*}" # take first part
    else
        echo "$subconfig"
    fi
}

get-compiler-from-config() {
    if [ "$#" -eq 1 ]; then
        config="$1"
    elif [ -n "$CI_CONFIG" ]; then
        config="$CI_CONFIG"
    fi
    
    # substitute eventually 2 times to handle "windows_vs-2015_x32" case
    subconfig="${config#*_}" # take last part
    if [[ "$subconfig" == *"_"* ]]; then
        echo "${subconfig%_*}" # take fist part
    else
        echo "$subconfig"
    fi
}

get-architecture-from-config() {
    if [ "$#" -eq 1 ]; then
        config="$1"
    elif [ -n "$CI_CONFIG" ]; then
        config="$CI_CONFIG"
    fi
    
    # substitute eventually 2 times to handle "windows_vs-2015_x32" case
    subconfig="${config#*_}" # take last part
    if [[ "$subconfig" == *"_"* ]]; then
        echo "${subconfig#*_}" # take last part
    else
        echo "amd64" # default architecture
    fi
}

save-env-vars() {
    if [ ! "$#" -eq 2 ]; then
        exit 1
    fi
    prefix="$1"
    output_dir="$2"
    env | grep "^${prefix}_" | grep -v "TOKEN" > "${output_dir}/${prefix}_vars.txt"
}

load-env-vars() {
    if [ ! "$#" -eq 2 ]; then
        exit 1
    fi
    prefix="$1"
    input_dir="$2"
    while IFS='' read -r line || [[ -n "$line" ]]; do
        export "$line"
    done < "${input_dir}/${prefix}_vars.txt"
}


