#!/bin/bash

usage() {
    echo "Usage: doxygen.sh <doxyfile> <modifiers>"
    echo "    modifiers are variables to override (e.g. \"PROJECT_NAME=MyFancyName\")"
}

script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$script_dir"

if [ $# -eq 0 ]; then
    usage; exit 1
fi

doxyfile="$1"; shift
if [ ! -e "$doxyfile" ]; then
    echo "Error: $doxyfile: file not found."
fi

cat "$doxyfile" > "$doxyfile.tmp"
echo "" >> "$doxyfile.tmp" # force newline

for arg in $*; do
    if [[ "$arg" == *"="* ]]; then
        echo "$arg" >> "$doxyfile.tmp"
    fi
done

doxygen "$doxyfile.tmp"

rm -f "$doxyfile.tmp"
