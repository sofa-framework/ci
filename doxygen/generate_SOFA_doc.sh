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
output_dir="$(cd "$1" && pwd)"; shift
doxyfile="$(realpath "$1")"; shift
VM_MAX_PARALLEL_THREADS=4
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
rm -f $output_dir/plugins_list*

# forward stop signals to child processes
# trap "kill -TERM ${pids[*]}" SIGINT SIGTERM EXIT
#trap "trap - SIGTERM && kill -- -$$" SIGINT SIGTERM EXIT


generate_plugin_doc() {
    plugin="$1"; shift
    # $@ now contains only the modifiers
    echo "  - Generating $plugin doc ..."
    doxyfile_copy="${output_dir}/${doxyfile_name}_${plugin}.dox"
    cp "$doxyfile" "$doxyfile_copy"
    local tagfiles="$(printf " \\ \n${output_dir}/tags/SOFA.tag=../../../sofa/html")"
    $script_dir/doxygen.sh "$doxyfile_copy" "$@" \
        "INPUT=${sofa_dir}/applications/plugins/${plugin}" \
        "OUTPUT_DIRECTORY=${output_dir}/doc/plugins/${plugin}" \
        "PROJECT_NAME=\"SOFA plugin: ${plugin}\"" \
        "HTML_HEADER=${script_dir}/custom_header.html" \
        "HTML_EXTRA_STYLESHEET=${script_dir}/custom_style.css" \
        "LAYOUT_FILE=${script_dir}/custom_layout.xml" \
        "TAGFILES=$tagfiles" \
        > "${output_dir}/logs/plugins/${plugin}.txt" 2>&1
    echo "  - $plugin doc generated."
}


echo "------------------------------"
echo "Listing plugins ..."
for plugin_dir in $sofa_dir/applications/plugins/*; do
    # generate all plugin tags in parallel
    if [ -d "$plugin_dir" ] && [ -e "$plugin_dir/CMakeLists.txt" ] &&
       [[ "$plugin_dir" != *"DEPRECATED"* ]] &&
       [[ "$plugin_dir" != *"PluginExample"* ]] &&
       [[ "$plugin_dir" != *"EmptyCmakePlugin"* ]]; then
        echo "$plugin_dir" >> $output_dir/plugins_list.txt
    fi
done
if [ -e "$(command -v shuf)" ]; then
    echo "$(shuf $output_dir/plugins_list.txt)" > "$output_dir/plugins_list.txt"
fi
total_lines="$(cat "$output_dir/plugins_list.txt" | wc -l)"
lines_per_thread=$(( total_lines / VM_MAX_PARALLEL_THREADS + 1 ))
split -l $lines_per_thread "$output_dir/plugins_list.txt" "$output_dir/plugins_list_part-"
for plugins_list in $output_dir/plugins_list_part-*; do
    echo "Plugins in $plugins_list:"
    cat $plugins_list
    echo "------"
done
echo "Plugins listed."


echo "------------------------------"
echo "Processing tags and generating plugins.dox ..."
echo "
/**
    \page plugins SOFA Plugins
    <ul>
" > $output_dir/plugins.dox
# tagfiles=""
while read plugin_dir; do
    plugin="${plugin_dir##*/}"
    # if [ -d "${output_dir}/doc/plugins/${tag_name}/html" ]; then
        # tagfiles="$(printf "$tagfiles \\ \n${output_dir}/tags/plugins/${plugin}.tag=../../plugins/${plugin}/html")"
    # fi

    echo "<li><a href=\"../../plugins/${plugin}/html/index.html\">${plugin}</a></li>" >> $output_dir/plugins.dox
done < "$output_dir/plugins_list.txt"
echo "
    </ul>
*/" >> $output_dir/plugins.dox
echo "Done."


echo "------------------------------"
echo "Generating SOFA doc ..."
doxyfile_copy="${output_dir}/${doxyfile_name}_kernel.dox"
cp "$doxyfile" "$doxyfile_copy"
$script_dir/doxygen.sh "$doxyfile_copy" "$@" \
    "INPUT=${output_dir}/plugins.dox ${script_dir}/mainpage.dox ${sofa_dir}/Sofa ${sofa_dir}/Component ${sofa_dir}/modules ${sofa_dir}/SofaKernel/modules" \
    "OUTPUT_DIRECTORY=${output_dir}/doc/sofa" \
    "PROJECT_NAME=\"SOFA API\"" \
    "HTML_HEADER=${script_dir}/custom_header.html" \
    "HTML_EXTRA_STYLESHEET=${script_dir}/custom_style.css" \
    "LAYOUT_FILE=${script_dir}/custom_layout.xml" \
    "GENERATE_TAGFILE=${output_dir}/tags/SOFA.tag" \
    > "${output_dir}/logs/sofa.txt" 2>&1
echo "SOFA doc generated."


echo "------------------------------"
echo "Generating plugins doc ..."
generate_plugin_doc_from_list() {
    plugins_list="$1"
    echo "Start of list: $plugins_list"
    while read plugin_dir; do
        plugin="${plugin_dir##*/}"
        generate_plugin_doc "$plugin" "$@"
    done < "$plugins_list"
    echo "End of list: $plugins_list"
}
for plugins_list in "$output_dir/plugins_list_part-"*; do
    generate_plugin_doc_from_list "$plugins_list" &
done
wait
echo "Plugins doc generated."
