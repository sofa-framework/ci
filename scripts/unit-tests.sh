#! /bin/bash

# This script runs all the googletest-based automatic tests it can find, assumed
# to be the executables in bin/ that match *_test, and saves the results in XML
# files, that can be understood by Jenkins.

# set -o errexit

# Disable colored output to avoid dirtying the log
export GTEST_COLOR=no
export SOFA_COLOR_TERMINAL=no

usage() {
    echo "Usage: unit-tests.sh (run|print-summary) <build-dir> <src-dir> [references-dir]"
}

if [ "$#" -ge 3 ]; then
    SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
    . "$SCRIPT_DIR"/utils.sh

    command="$1"
    build_dir="$(cd $2 && pwd)"
    src_dir="$(cd $3 && pwd)"
    test_type="unit-tests"
    if [ -n "$4" ]; then
        test_type="regression-tests"
        references_dir="$4"
    fi
    output_dir="$test_type"
else
    usage; exit 1
fi

cd "$build_dir"

if [[ ! -d "$build_dir/lib/" ]]; then
    echo "Error: '$build_dir' does not look like a Sofa build."
    usage; exit 1
elif [[ ! -d "$src_dir/applications/plugins" ]]; then
    echo "Error: '$src_dir' does not look like a Sofa source tree."
    usage; exit 1
fi
if [ -z "$VM_MAX_PARALLEL_TESTS" ]; then
    VM_MAX_PARALLEL_TESTS=1
fi

# export SOFA_DATA_PATH="$src_dir:$src_dir/examples:$src_dir/share"
export SOFA_ROOT="$build_dir"
if [[ "$test_type" == "regression-tests" ]]; then
    export REGRESSION_REFERENCES_DIR="$references_dir/examples|$references_dir/applications/plugins"
    export REGRESSION_SCENES_DIR="$src_dir/examples|$src_dir/applications/plugins"
fi

list-tests() {
    pushd "$build_dir/bin" > /dev/null
    if [[ "$test_type" == "regression-tests" ]]; then
        for file in *; do
            if [[ "$file" == Regression_test ]]     || [[ "$file" == Regression_testd ]] ||
               [[ "$file" == Regression_test.exe ]] || [[ "$file" == Regression_testd.exe ]]; then
                echo $file
            fi
        done
    else
        for file in *; do
            if [[ "$file" == Regression_test ]]     || [[ "$file" == Regression_testd ]] ||
               [[ "$file" == Regression_test.exe ]] || [[ "$file" == Regression_testd.exe ]]; then
                continue # ignore regression tests
            fi
            if [[ "$file" == *_test ]]         || [[ "$file" == *_testd ]] ||
               [[ "$file" == *_test.exe ]]     || [[ "$file" == *_testd.exe ]] ||
               [[ "$file" == *_simutest ]]     || [[ "$file" == *_simutestd ]] ||
               [[ "$file" == *_simutest.exe ]] || [[ "$file" == *_simutestd.exe ]]; then
                echo $file
            elif [[ "$file" == *.Tests ]]      || [[ "$file" == *.Testsd ]] ||
                 [[ "$file" == *.Tests.exe ]]  || [[ "$file" == *.Testsd.exe ]]; then
                # SofaPython3 unit tests
                echo $file
            fi
        done
    fi
    popd > /dev/null
}

initialize-unit-tests() {
    echo "Initializing unit testing."
    rm -rf "$output_dir"
    mkdir -p "$output_dir/reports"
    list-tests | while read test; do
        echo "$test"
        mkdir -p "$output_dir/$test"
    done > "$output_dir/$test_type.txt"
}

fix-test-report() {
    local report_file="$1"
    local test_name="$2"
    test_name="${test_name%.*}" # remove eventual extension
    local package="UnitTests"
    if [[ "$test_type" == "regression-tests" ]]; then
        package="RegressionTests"
    fi

    if [[ "$test_name" == "Sofa."* ]]; then
        test_name=Sofa_"${test_name#*.}"
    elif [[ "$test_name" == "Bindings."* ]]; then
        test_name=Bindings_"${test_name#*.}"
    fi

    # Little fix: Googletest marks skipped tests with a 'status="notrun"' attribute,
    # but the JUnit XML understood by Jenkins requires a '<skipped/>' element instead.
    # source: http://stackoverflow.com/a/14074664
    sed -i'.bak' 's:\(<testcase [^>]*status="notrun".*\)/>:\1><skipped/></testcase>:' "$report_file"
    rm -f "$report_file.bak"

    sed -i'.bak' 's:\(<testsuite [^>]*\)>:\1 package="'"$test_name"'">:g' "$report_file"
    rm -f "$report_file.bak"

    # Add a package name by inserting "UnitTest." in front of the classname attribute of each testcase
    sed -i'.bak' 's:^\(.*<testcase[^>]* classname=\"\)\([^\"]*\".*\)$:\1'"$package"'\.'"$test_name"'/\2:g' "$report_file"
    rm -f "$report_file.bak"

    # Transform JUnit report navigation for typed tests into
    #   - SofaGeneralEngine_test/TransformEngine_test
    #       > 1/input, 1/rotation, 1/scale, ...
    #       > 2/input, 2/rotation, 2/scale, ...
    #       > ...
    # instead of
    #   - SofaGeneralEngine_test/TransformEngine_test/1
    #       > input, rotation, scale, ...
    #   - SofaGeneralEngine_test/TransformEngine_test/2
    #       > input, rotation, scale, ...
    #   - ...
    #                 |----------- 1 -----------| |-- 2 --| |------------ 3 ------------|  |-- 4 --| |- 5 -|
    sed -i'.bak' 's:^\(.*<testcase[^>]* name=\"\)\([^\"]*\)\(\"[^>]* classname=\"[^\"]*\)/\([0-9]*\)\(\".*\)$:\1\2/\4\3\5:g' "$report_file"
    rm -f "$report_file.bak"

    # Protect against invalid XML characters in the CDATA sections
    if vm-is-macos && [[ "$(which sed)" != *"gnu-sed"* ]]; then
        sed -i'.bak' $'s:[\x00-\x08]::g ; s:\x0B::g ; s:\x0C::g ; s:[\x0E-\x1F]::g' "$report_file"
    else
        sed -i'.bak'  's:[\x00-\x08]::g ; s:\x0B::g ; s:\x0C::g ; s:[\x0E-\x1F]::g' "$report_file"
    fi
    rm -f "$report_file.bak"
}


run-single-test-subtests() {
    local test=$1

    # List all the subtests in this test
    bash -c "$build_dir/bin/$test --gtest_list_tests > $output_dir/$test/subtests.tmp.txt"
    IFS=''; while read line; do
        if echo "$line" | grep -q "^  [^ ][^ ]*" ; then
            local current_subtest="$(echo "$line" | sed 's/^  \([^ ][^ ]*\).*/\1/g')"
            echo "$current_test.$current_subtest" >> "$output_dir/$test/subtests.txt"
        elif echo "$line" | grep -q "^[^ ][^ ]*\." ; then
            local current_test="$(echo "$line" | sed 's/\..*//g')"
        fi
    done < "$output_dir/$test/subtests.tmp.txt"
    rm -f "$output_dir/$test/subtests.tmp.txt"

    # Run the subtests
    printf "\n\nRunning $test subtests\n"
    local i=1;
    while read subtest; do
        local output_file="$output_dir/$test/$subtest/report.xml"
        local test_cmd="$build_dir/bin/$test --gtest_output=xml:$output_file --gtest_filter=$subtest 2>&1"
        mkdir -p "$output_dir/$test/$subtest"
        echo "$test_cmd" >> "$output_dir/$test/$subtest/command.txt"

        ( echo "" &&
          echo "------------------------------------------" &&
          echo "" &&
          echo "Running $test_type subtest $subtest" &&
          echo 'Calling: bash -c "'$test_cmd'"' &&
          echo ""
        ) > "$output_dir/$test/$subtest/output.txt"

        begin_millisec="$(time-millisec)"
        bash -c "$test_cmd" >> "$output_dir/$test/$subtest/output.txt" ; pipestatus="${PIPESTATUS[0]}"
        end_millisec="$(time-millisec)"

        # Log on stdout
        echo "$( printf "\n\n" && cat "$output_dir/$test/$subtest/output.txt" )"

        elapsed_millisec="$(( end_millisec - begin_millisec ))"
        elapsed_sec="$(( elapsed_millisec / 1000 )).$(printf "%03d" $elapsed_millisec)"

        echo "$pipestatus" > "$output_dir/$test/$subtest/status.txt"
        if [ $pipestatus -gt 1 ]; then # this subtest crashed (0:OK 1:failure >1:crash)
            IFS='.' read -r -a array <<< "$subtest"
            test_name="${array[0]}"
            subtest_name="${array[1]}"
            echo "$0: error: $subtest ended with code $pipestatus" >&2
            # Write the XML output by hand
            echo '<?xml version="1.0" encoding="UTF-8"?>
<testsuites tests="1" failures="0" disabled="0" errors="1" time="-'"$elapsed_sec"'" name="AllTests">
    <testsuite name="'"$test_name"'" tests="1" failures="0" disabled="0" errors="1" time="-'"$elapsed_sec"'">
        <testcase name="'"$subtest_name"'" type_param="" status="run" time="-'"$elapsed_sec"'" classname="'"$test_name"'">
            <error message="[CRASH] '"$subtest"' ended with code '"$pipestatus"'">
<![CDATA['"$(cat $output_dir/$test/$subtest/output.txt)"']]>
            </error>
        </testcase>
    </testsuite>
</testsuites>' > "$output_file"
        fi

        if [ -f "$output_file" ]; then
            fix-test-report "$output_file" "$test"
            cp "$output_file" "$output_dir/reports/"$test"_subtest"$(printf "%03d" $i)".xml"
        else
            echo "$0: error: $test subtest $subtest ended with code $(cat $output_dir/$test/$subtest/status.txt)" >&2
        fi
        i=$(( i + 1 ))
    done < "$output_dir/$test/subtests.txt"
}

run-single-test() {
    local test=$1
    local output_file="$output_dir/$test/report.xml"
    local test_cmd="$build_dir/bin/$test --gtest_output=xml:$output_file 2>&1"
    rm -f "$output_file"

    ( echo "" &&
      echo "------------------------------------------" &&
      echo "" &&
      echo "Running $test_type $test" &&
      echo 'Calling: bash -c "'$test_cmd'"' &&
      echo ""
    ) > "$output_dir/$test/output.txt"

    bash -c "$test_cmd" >> "$output_dir/$test/output.txt" ; status="${PIPESTATUS[0]}"

    echo "$test_cmd" > "$output_dir/$test/command.txt"
    echo "$status" > "$output_dir/$test/status.txt"

    # Log on stdout
    echo "$( printf "\n\n" && cat "$output_dir/$test/output.txt" )"

    if [ -f "$output_file" ]; then
        if [ "$status" -gt 1 ]; then # report exists but gtest crashed
            echo "$0: fatal: unexpected crash of $test with code $status" >&2
        fi
        fix-test-report "$output_file" "$test"
        cp "$output_file" "$output_dir/reports/$test.xml"
    else # no report = some subtest crashed. Let's find out which one.
        echo "$0: error: $test ended with code $status" >&2
        # Run each subtest of this test to avoid results loss
        run-single-test-subtests "$test"
    fi
}

do-run-all-tests() {
    local file="$1"
    while read test; do
        run-single-test "$test"
    done < "$file"
}

run-all-tests() {
    echo "Unit testing in progress..."

    # Move SofaPython3 tests out of the list
    cat "$output_dir/${test_type}.txt" | grep "Bindings\." > "$output_dir/${test_type}.SofaPython3.txt"
    cat "$output_dir/${test_type}.txt" | grep -v "Bindings\." > "$output_dir/${test_type}.txt.tmp"
    cp -f "$output_dir/${test_type}.txt.tmp" "$output_dir/${test_type}.txt" && rm -f "$output_dir/${test_type}.txt.tmp"

    if [ -e "$(command -v shuf)" ]; then
        echo "$(shuf $output_dir/${test_type}.txt)" > "$output_dir/${test_type}.txt"
    fi
    local total_lines="$(cat "$output_dir/${test_type}.txt" | wc -l)"
    local lines_per_thread=$((total_lines / VM_MAX_PARALLEL_TESTS + 1))
    split -l $lines_per_thread "$output_dir/${test_type}.txt" "$output_dir/${test_type}_part-"

    # Add SofaPython3 tests in first part
    cat "$output_dir/${test_type}.SofaPython3.txt" >> "$output_dir/${test_type}_part-aa"

    thread=0
    for file in "$output_dir/${test_type}_part-"*; do
        do-run-all-tests "$file" &
        pids[${thread}]=$!
        thread=$(( thread + 1 ))
    done
    # forward stop signals to child processes
    trap "trap - SIGTERM && kill -- -$$" SIGINT SIGTERM EXIT
    # wait for all pids
    thread=0
    for file in "$output_dir/${test_type}_part-"*; do
        echo "Waiting for thread $(( thread + 1 ))/$VM_MAX_PARALLEL_TESTS (PID ${pids[$thread]}) to finish..."
        wait ${pids[$thread]}
        echo "Thread $(( thread + 1 ))/$VM_MAX_PARALLEL_TESTS (PID ${pids[$thread]}) is done."
        thread=$(( thread + 1 ))
    done
    echo "Done."
}

count-test-suites() {
    list-tests | wc -w | tr -d ' '
}
count-test-reports() {
    ls "$output_dir/reports/" --ignore="*subtest*" 2> /dev/null | wc -l | tr -d ' '
}
count-crashes() {
    echo "$(( $(count-test-suites) - $(count-test-reports) ))"
}

# Fetch the <testsuites> XML elements in reports/*.xml,
# extract and sum the attribute given in argument
# This function relies on the element being written on a single line:
# E.g. <testsuites tests="212" failures="4" disabled="0" errors="0" ...
tests-get()
{
    # Check the existence of report files
    if ! ls "$output_dir/reports/"*.xml &> /dev/null; then
        echo 0
        return
    fi
    attribute="$1"

    # grep the lines containing '<testsuites'; for each one, match the
    # 'attribute="..."' pattern, and collect the "..." part
    counts=$(sed -ne 's/.*<testsuites[^>]* '"$attribute"'="//' \
                 -e '/^[0-9]/s/".*//p' "$output_dir/reports/"*.xml)
    # if count is empty, retry with testcase
    if [ -z "$counts" ]; then
        counts=$(sed -ne 's/.*<testcase[^>]* '"$attribute"'="//' \
                     -e '/^[0-9]/s/".*//p' "$output_dir/reports/"*.xml)
    fi

    # sum the values
    local python_exe="$(find-python)"
    total=0
    for value in $counts; do
        total="$( $python_exe -c "print($total + $value)" )"
    done
    echo "$total"
}

print-summary() {
    echo "Testing summary:"
    echo "- $(count-test-suites) test suite(s)"
    echo "- $(tests-get tests) test(s)"
    echo "- $(tests-get disabled) disabled test(s)"
    echo "- $(tests-get failures) failure(s)"

    local errors="$(tests-get errors)"
    echo "- $errors error(s)"
    if [[ "$errors" != 0 ]]; then
        while read test; do
            if [[ ! -e "$output_dir/$test/report.xml" ]]; then # this test crashed
                local status="$(cat "$output_dir/$test/status.txt")"
                case "$status" in
                    "timeout")
                        echo "  - Timeout: $test"
                        ;;
                    [0-9]*)
                        if [[ "$status" -gt 128 && ( $(uname) = Darwin || $(uname) = Linux ) ]]; then
                            echo "  - Exit with status $status ($(kill -l $status)): $test"
                        elif [[ "$status" != 0 ]]; then
                            echo "  - Exit with status $status: $test"
                        fi
                        ;;
                    *)
                        echo "Error: unexpected value in $output_dir/$test/status.txt: $status"
                        ;;
                esac
            fi
        done < "$output_dir/$test_type.txt"
    fi
}

if [[ "$command" = run ]]; then
    initialize-unit-tests
    run-all-tests
elif [[ "$command" = count-durations ]]; then
    tests-get time
elif [[ "$command" = count-tests ]]; then
    tests-get tests
elif [[ "$command" = count-failures ]]; then
    tests-get failures
elif [[ "$command" = count-disabled ]]; then
    tests-get disabled
elif [[ "$command" = count-errors ]]; then
    tests-get errors
elif [[ "$command" = count-test-suites ]]; then
    count-test-suites
elif [[ "$command" = count-crashes ]]; then
    count-crashes
elif [[ "$command" = print-summary ]]; then
    print-summary
else
    usage
fi
