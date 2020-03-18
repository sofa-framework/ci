#!/bin/bash
set -e

source /opt/rh/devtoolset-7/enable || true
source /opt/rh/llvm-toolset-7/enable || true

exec "$@"
