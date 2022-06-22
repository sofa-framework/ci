#!/bin/bash
#set -e

ulimit -c 0 # disable core dumps

for dir in "$QT_INSTALLDIR/Tools/QtInstallerFramework/"*; do
    if [ -d "$dir" ]; then
        export QTIFWDIR="$dir" # take the first one
        break
    fi
done
if [ -n "$QTIFWDIR" ]; then
    export PATH="$QTIFWDIR/bin${PATH:+:${PATH}}"
fi

exec "$@"
