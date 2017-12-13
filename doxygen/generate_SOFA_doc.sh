#!/bin/bash
set -o errexit # Exit on error


usage() {
    echo "Usage: generate_SOFA_doc.sh <sofa_dir> <output_dir> <doxyfile> <modifiers>"
    echo "    modifiers are variables to override (e.g. \"PROJECT_NAME=MyFancyName\")"
}

if [ $# -lt 4 ]; then
    usage; exit 1
fi

# Read args
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
sofa_dir="$(cd "$1" && pwd)"; shift
output_dir="$(mkdir -p "$1" && cd "$1" && pwd)"; shift
doxyfile="$(realpath "$1")"; shift
# $@ now contains only the modifiers

# Normalize Windows paths: /c/windows/path -> c:/windows/path
script_dir="$(echo $script_dir | sed -e 's/\/\([a-zA-Z]\)\//\1:\//g')" 
sofa_dir="$(echo $sofa_dir | sed -e 's/\/\([a-zA-Z]\)\//\1:\//g')"
output_dir="$(echo $output_dir | sed -e 's/\/\([a-zA-Z]\)\//\1:\//g')"
doxyfile="$(echo $doxyfile | sed -e 's/\/\([a-zA-Z]\)\//\1:\//g')"

doxyfile_file="${doxyfile##*/}"
doxyfile_name="${doxyfile_file%.*}"

if [ ! -d "$sofa_dir/applications" ] ||
   [ ! -d "$sofa_dir/modules" ]; then
   echo "Error: $sofa_dir does not seem to be a SOFA directory."; exit 1
fi

mkdir -p "${output_dir}/logs/plugins"
mkdir -p "${output_dir}/tags/plugins"
mkdir -p "${output_dir}/doc/plugins"
mkdir -p "${output_dir}/doc/sofa"

generate_plugin_tags() {
    plugin_dir="$1"; shift
    # $@ now contains only the modifiers

    if [ -d "$plugin_dir" ] && [[ ! "$plugin_dir" == *"DEPRECATED"* ]]; then
        plugin="${plugin_dir##*/}"
        doxyfile_copy="${output_dir}/${doxyfile_name}_${plugin}.dox"
        cp "$doxyfile" "$doxyfile_copy"
        echo "Executing doxygen on $plugin"
        $script_dir/doxygen.sh "$doxyfile_copy" "$@" "INPUT=${sofa_dir}/applications/plugins/${plugin}" "OUTPUT_DIRECTORY=${output_dir}/doc/plugins/${plugin}" "PROJECT_NAME=\"SOFA plugin: ${plugin}\"" "HTML_HEADER=${script_dir}/custom_header.html" "GENERATE_TAGFILE=${output_dir}/tags/plugins/${plugin}.tag" > "${output_dir}/logs/plugins/${plugin}.txt" 2>&1
    fi
}
for plugin_dir in $sofa_dir/applications/plugins/*; do
    generate_plugin_tags "$plugin_dir" "$@" &
done
wait
echo "Plugins doc generated."

# echo "Executing doxygen on modules"
# doxyfile_copy="${doxyfile_name}_modules.dox"
# cp "$doxyfile" "$doxyfile_copy"
# mkdir -p "doc/modules"
# ./doxygen.sh "$doxyfile_copy" "INPUT=${sofa_dir}/modules" "OUTPUT_DIRECTORY=${output_dir}/doc/modules" "PROJECT_NAME=SOFA_modules" "GENERATE_TAGFILE=tags/modules.tag" > "logs/modules.tag.txt" 2>&1
# rm "$doxyfile_copy"

echo "Executing doxygen on SOFA"
doxyfile_copy="${output_dir}/${doxyfile_name}_kernel.dox"
cp "$doxyfile" "$doxyfile_copy"

# Process tags and plugins.dox
echo "
/**
    \page plugins \"SOFA Plugins\"
    <ul>
" > $sofa_dir/plugins.dox
for tag in $output_dir/tags/plugins/*; do
    tag_file="${tag##*/}"
    tag_name="${tag_file%.*}"
    if [ -d "${output_dir}/doc/plugins/${tag_name}/html" ]; then
        tagfiles="$(printf "$tagfiles \\ \n${tag}=../../plugins/${tag_name}/html")"
    fi

    echo "<li><a href=\"plugins/${tag_name}/html/index.html\">${tag_name}</a></li>  " >> $sofa_dir/plugins.dox
done
echo "
    </ul>
*/" >> $sofa_dir/plugins.dox

# Add main page
cp -f $script_dir/mainpage.dox $sofa_dir/mainpage.dox

$script_dir/doxygen.sh "$doxyfile_copy" "$@" "INPUT=${sofa_dir}/modules ${sofa_dir}/SofaKernel" "OUTPUT_DIRECTORY=${output_dir}/doc/sofa" "PROJECT_NAME=\"SOFA API\"" "HTML_HEADER=${script_dir}/custom_header.html" "TAGFILES=$tagfiles"

echo "Modules and Kernel doc generated."

