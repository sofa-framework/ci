#!/bin/bash
#set -e

ulimit -c 0 # disable core dumps

exec "$@"
