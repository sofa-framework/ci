#!/bin/bash
set -e

source /opt/rh/devtoolset-7/enable
source /opt/rh/llvm-toolset-7/enable
source /opt/rh/python27/enable
source /opt/rh/rh-python38/enable

exec "$@"
