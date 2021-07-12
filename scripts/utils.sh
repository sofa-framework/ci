#!/bin/bash
# set -o errexit # Exit on error

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

find-python() {
    if [ -e "$VM_PYTHON3_EXECUTABLE" ]; then
        python_exe="$VM_PYTHON3_EXECUTABLE"
    elif [ -x "$(command -v "python3")" ]; then
        python_exe="python3"
    elif [ -e "$VM_PYTHON_EXECUTABLE" ]; then
        python_exe="$VM_PYTHON_EXECUTABLE"
    elif [ -x "$(command -v "python")" ]; then
        python_exe="python"
    elif [ -n "$CI_PYTHON_CMD" ]; then
        python_exe="$CI_PYTHON_CMD"
    else
        >&2 echo "WARNING: Python executable not found. Try setting VM_PYTHON3_EXECUTABLE variable."
        python_exe=""
    fi
    if [[ "$CI_PYTHON_CMD" != "$python_exe" ]]; then
        export CI_PYTHON_CMD="$python_exe"
    fi
    echo "$python_exe"
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
    find-python
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
            vs-2019) echo "2019" ;;
        esac
    fi
}

get-msvc-comntools() {
    if vm-is-windows; then
        local compiler="$(echo "$1" | tr '[:upper:]' '[:lower:]')"
        case "$compiler" in
            vs-2012) echo "VS110COMNTOOLS" ;;
            vs-2013) echo "VS120COMNTOOLS" ;;
            vs-2015) echo "VS140COMNTOOLS" ;;
            vs-2017) echo "VS150COMNTOOLS" ;;
            vs-2019) echo "VS160COMNTOOLS" ;;
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
    # Check env vars for build options (also check args)
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
    if [[ "$7" == "true" ]] || [[ "$CI_RUN_REGRESSION_TESTS" == "true" ]]; then
        build_options="run-regression-tests $build_options"
    fi
    if [[ "$8" == "true" ]] || [[ "$CI_PLUGINS" == "package" ]]; then
        build_options="build-release-package $build_options"
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

generator() {
    if [ -x "$(command -v ninja)" ]; then
        echo "Ninja"
    elif vm-is-windows; then
        echo "\"NMake Makefiles\""
    else
        echo "Unix Makefiles"
    fi
}

count-processes() {
    echo "$(ps -ef | grep -v grep | grep "$1" | wc -l)"
}

time-date() {
    local python_exe="$(find-python)"
    if [ -n "$python_exe" ]; then
        $python_exe -c 'from datetime import datetime; print(datetime.now())'
    else
        if vm-is-macos && [ -e "/usr/local/bin/gdate" ]; then
            date_cmd="/usr/local/bin/gdate"
        else
            date_cmd="date"
        fi
        date="$($date_cmd)"
        echo "$date"
    fi
}

time-millisec() {
    local python_exe="$(find-python)"
    if [ -n "$python_exe" ]; then
        $python_exe -c 'import time; print("%d" % (time.time()*1000))'
    else
        if vm-is-macos; then
            if [ -e "/usr/local/bin/gdate" ]; then
                date_nanosec_cmd="/usr/local/bin/gdate +%s%N"
            else
                date_nanosec_cmd="date +%s000000000" # fallback: seconds * 1000000000
            fi
        else
            date_nanosec_cmd="date +%s%N"
        fi
        date_nanosec="$($date_nanosec_cmd)"
        echo "$(( date_nanosec / 1000000 ))"
    fi
}

time-elapsed-sec() {
    local begin_millisec="$1"
    local end_millisec="$2"
    elapsed_millisec="$(( end_millisec - begin_millisec ))"
    elapsed_sec="$(( elapsed_millisec / 1000 )).$(printf "%03d" $elapsed_millisec)"
    echo "$elapsed_sec"
}

call-cmake() {
    build_dir="$(cd "$1" && pwd)"
    shift # Remove first arg

    cmake_command="cmake"
    if [[ "$CI_DEBUG" == "true" ]]; then
        cmake_command="cmake --trace"
    fi

    if vm-is-windows; then
        msvc_comntools="$(get-msvc-comntools $COMPILER)"
        msvc_year="$(get-msvc-year $COMPILER)"
        # Call vcvarsall.bat first to setup environment
        if [ $msvc_year -le 2015 ]; then
            vcvarsall="call \"%${msvc_comntools}%\\..\\..\\VC\vcvarsall.bat\" $ARCHITECTURE"
        else
            vcvarsall="cd %VSINSTALLDIR% && call %${msvc_comntools}%\\VsDevCmd -host_arch=amd64 -arch=$ARCHITECTURE"
        fi
        build_dir_windows="$(cd "$build_dir" && pwd -W | sed 's#/#\\#g')"
        if [ -n "$EXECUTOR_LINK_WINDOWS_BUILD" ]; then
            build_dir_windows="$EXECUTOR_LINK_WINDOWS_BUILD"
        fi
        if [ $msvc_year -le 2015 ]; then
            echo "Calling: $COMSPEC /c \"$vcvarsall & cd $build_dir_windows & $cmake_command $*\""
            $COMSPEC /c "$vcvarsall & cd $build_dir_windows & $cmake_command $*"
        else
            echo "Calling: $COMSPEC //c \"$vcvarsall && cd $build_dir_windows && $cmake_command $*\""
            $COMSPEC //c "$vcvarsall && cd $build_dir_windows && $cmake_command $*"
        fi
    else
        echo "Calling: $cmake_command $@"
        cd $build_dir && $cmake_command "$@"
    fi
}

call-make() {
    build_dir="$(cd "$1" && pwd)"
    target="$2"

    if vm-is-windows; then
        msvc_comntools="$(get-msvc-comntools $COMPILER)"
        msvc_year="$(get-msvc-year $COMPILER)"
        # Call vcvarsall.bat first to setup environment
        if [ $msvc_year -le 2015 ]; then
            vcvarsall="call \"%${msvc_comntools}%\\..\\..\\VC\vcvarsall.bat\" $ARCHITECTURE"
        else
            vcvarsall="cd %VSINSTALLDIR% && call %${msvc_comntools}%\\VsDevCmd -host_arch=amd64 -arch=$ARCHITECTURE"
        fi
        toolname="nmake" # default
        if [ -x "$(command -v ninja)" ]; then
        	echo "Using ninja as build system"
            toolname="ninja"
        fi
        build_dir_windows="$(cd "$build_dir" && pwd -W | sed 's#/#\\#g')"
        if [ -n "$EXECUTOR_LINK_WINDOWS_BUILD" ]; then
            build_dir_windows="$EXECUTOR_LINK_WINDOWS_BUILD"
        fi
        if [ $msvc_year -le 2015 ]; then
            echo "Calling: $COMSPEC /c \"$vcvarsall & cd $build_dir_windows & $toolname $target $VM_MAKE_OPTIONS\""
            $COMSPEC /c "$vcvarsall & cd $build_dir_windows & $toolname $target $VM_MAKE_OPTIONS"
        else
            echo "Calling: $COMSPEC //c \"$vcvarsall && cd $build_dir_windows && $toolname $target $VM_MAKE_OPTIONS\""
            $COMSPEC //c "$vcvarsall && cd $build_dir_windows && $toolname $target $VM_MAKE_OPTIONS"
        fi
    else
    	toolname="make" # default
        if [ -x "$(command -v ninja)" ]; then
            echo "Using ninja as build system"
	        toolname="ninja"
        fi
        echo "Calling: $toolname $target $VM_MAKE_OPTIONS"
        cd $build_dir && $toolname $target $VM_MAKE_OPTIONS
    fi
}
