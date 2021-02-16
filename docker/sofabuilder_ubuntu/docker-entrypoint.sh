#!/bin/bash
#set -e

ulimit -c 0 # disable core dumps

source /opt/qt512/bin/qt512-env.sh

exec "$@"
