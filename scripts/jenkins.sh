#!/bin/bash
set -o errexit # Exit on error
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
. "$SCRIPT_DIR"/utils.sh
. "$SCRIPT_DIR"/dashboard.sh # needed for dashboard-config-string()

# usage: 
#   jenkins-get-last-node-for-pr "1799" "CI_CONFIG=$CI_CONFIG,CI_PLUGINS=$CI_PLUGINS,CI_TYPE=$CI_TYPE"
jenkins-get-last-node-for-pr() 
{
    local pr_id="$1"
    local ci_config="$2"
    response="$(curl --silent "https://ci.inria.fr/sofa-ci-dev/job/sofa-framework/job/PR-$pr_id/$ci_config/lastBuild/api/json?pretty=true")"
    echo $response
    if [ -n "$response" ]; then
        last_built_on_machine="$( echo "$response" | $python_exe -c "import sys; import json; print(json.load(sys.stdin)['builtOn'])")"
        echo ${last_built_on_machine}
    else
        echo "undefine"
    fi
}

# usage: 
#   jenkins-get-first-node-for-pr "1799" "CI_CONFIG=$CI_CONFIG,CI_PLUGINS=$CI_PLUGINS,CI_TYPE=$CI_TYPE"
jenkins-get-first-node-for-pr() 
{
    local pr_id="$1"
    local ci_config="$2"
    response="$(curl --silent "https://ci.inria.fr/sofa-ci-dev/job/sofa-framework/job/PR-$pr_id/$ci_config/1/api/json?pretty=true")"
    echo $response
    if [ -n "$response" ]; then
        first_built_on_machine="$( echo "$response" | $python_exe -c "import sys; import json; print(json.load(sys.stdin)['builtOn'])")"
        echo ${first_built_on_machine}
    else
        echo "undefine"
    fi
}

