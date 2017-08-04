#!/bin/bash


usage() {
    echo "Usage: generate_SOFA_doc.sh <sofa_dir> <doxyfile> <modifiers>"
    echo "    modifiers are variables to override (e.g. \"PROJECT_NAME=MyFancyName\")"
}

script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
sofa_dir="$(cd "$1" && pwd)"; shift
doxyfile="$(realpath "$1")"; shift

script_dir="$(echo $script_dir | sed -e 's/\/\([a-zA-Z]\)\//\1:\//g')"
sofa_dir="$(echo $sofa_dir | sed -e 's/\/\([a-zA-Z]\)\//\1:\//g')"
doxyfile="$(echo $doxyfile | sed -e 's/\/\([a-zA-Z]\)\//\1:\//g')"
doxyfile_name="${doxyfile%.*}"

if [ ! -d "$sofa_dir/applications" ] ||
   [ ! -d "$sofa_dir/modules" ]; then
   echo "Error: $sofa_dir does not seem to be a SOFA directory."; exit 1
fi

cd "$script_dir"
rm -rf "logs"
rm -rf "tags"
rm -rf "doc"
mkdir -p "logs/plugins"
mkdir -p "tags/plugins"
mkdir -p "doc/plugins"

generate_plugin_tags () {
    plugin_dir="$1"
    if [ -d "$plugin_dir" ] && [[ ! "$plugin_dir" == *"DEPRECATED"* ]]; then
        plugin="${plugin_dir##*/}"
        output_dir="${script_dir}/doc/plugins/${plugin}"
        rm -rf "$output_dir"; mkdir -p "$output_dir"
        doxyfile_tmp="${doxyfile_name}_${plugin}.dox"
        cp "$doxyfile" "$doxyfile_tmp"
        echo "Executing doxygen on $plugin"
        # ./doxygen.sh "$doxyfile_tmp" "INPUT=${sofa_dir}/applications/plugins/${plugin}" "OUTPUT_DIRECTORY=$output_dir" "PROJECT_NAME=\"SOFA plugin: ${plugin}\"" > "logs/${plugin}.txt" 2>&1
        ./doxygen.sh "$doxyfile_tmp" "INPUT=${sofa_dir}/applications/plugins/${plugin}" "OUTPUT_DIRECTORY=$output_dir" "PROJECT_NAME=\"SOFA plugin: ${plugin}\"" "GENERATE_TAGFILE=tags/plugins/${plugin}.tag" > "logs/${plugin}.txt" 2>&1
        rm "$doxyfile_tmp"
    fi
}
for plugin_dir in $sofa_dir/applications/plugins/*; do
    generate_plugin_tags "$plugin_dir" &
done
wait
echo "Plugins doc generated."

echo "Executing doxygen on modules"
doxyfile_tmp="${doxyfile_name}_modules.dox"
cp "$doxyfile" "$doxyfile_tmp"
mkdir -p "doc/modules"
# ./doxygen.sh "$doxyfile" "INPUT=${sofa_dir}/modules" "OUTPUT_DIRECTORY=${script_dir}/doc/modules" "PROJECT_NAME=\"SOFA modules\"" > "logs/modules.txt" 2>&1 &
./doxygen.sh "$doxyfile" "INPUT=${sofa_dir}/modules" "OUTPUT_DIRECTORY=${script_dir}/doc/modules" "PROJECT_NAME=\"SOFA modules\"" "GENERATE_TAGFILE=tags/modules.tag" > "logs/modules.tag.txt" 2>&1
rm "$doxyfile_tmp"

echo "Executing doxygen on kernel"
doxyfile_tmp="${doxyfile_name}kernel.dox"
cp "$doxyfile" "$doxyfile_tmp"
plugin_tags=""
for tag_file in $script_dir/tags/plugins/*; do
    tag="${tag_file%.*}"
    plugin_tags="$plugin_tags ${tag_file}=${script_dir}/doc/plugins/${tag}/html"
done
echo "TAGFILES=$plugin_tags tags/modules.tag"
exit
./doxygen.sh "$doxyfile" "INPUT=${sofa_dir}/SofaKernel" "OUTPUT_DIRECTORY=${script_dir}/doc/sofa" "PROJECT_NAME=\"SOFA API\"" "TAGFILES=$plugin_tags ${script_dir}/tags/modules.tag=${script_dir}/doc/modules/html" > "logs/kernel.txt" 2>&1 &
rm "$doxyfile_tmp"

wait
echo "Modules and Kernel doc generated."

