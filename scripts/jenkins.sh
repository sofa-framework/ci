#!/bin/bash
set -o errexit # Exit on error
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
. "$SCRIPT_DIR"/utils.sh
. "$SCRIPT_DIR"/dashboard.sh # needed for dashboard-config-string()

# usage: 
#   jenkins-get-last-node-for-pr "PR-1735" "CI_CONFIG=$CI_CONFIG,CI_PLUGINS=$CI_PLUGINS,CI_TYPE=$CI_TYPE"
jenkins-get-last-node-for-pr() 
{
    local pr_id="$1"
    local ci_config="$2"
    response="$(curl --silent "https://ci.inria.fr/sofa-ci-dev/job/sofa-framework/job/$pr_id/$ci_config/lastBuild/api/json?pretty=true")"
    
    if [ -n "$response" ]; then
        last_built_on_machine="$( echo "$response" | $python_exe -c "import sys; import json; print(json.load(sys.stdin)['builtOn'])")"
        echo ${last_built_on_machine}
    else
        echo "undefine"
    fi
}


