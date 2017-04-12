#!/bin/bash
pwd
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
. "$SCRIPT_DIR"/dashboard.sh

# We need dashboard env vars in case of abort
dashboard-export-vars ${*:3}

child=9999999999
onAbort()
{
    kill -SIGKILL $child
    echo "--------- ABORT TRAPPED ---------"
    dashboard-notify "status=aborted"
}
trap onAbort SIGINT SIGTERM

# set -euf -o pipefail
echo Process group id is $$
echo "---"

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
"$SCRIPT_DIR/main.sh" "$@" &
child=$!

wait $child