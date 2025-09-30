#!/bin/bash

#################
#### WARNING 
#### Parts of this script is meant to be changed for the real deployement
#### - https://github.com/bakpaul/sofa --> https://github.com/sofa-framework/sofa
#### - https://github.com/bakpaul/ci --> https://github.com/sofa-framework/ci
#### - remove checking out jenkins_gha_migration branch of ci repository.
#################

usage() {
    echo "Usage: unix.sh <install-dir> <github-package-full-version (e.g. 2.328.0)> <configure-token>"
    echo "<github-package-full-version> and <configure-token> can be found on https://github.com/bakpaul/sofa/settings/actions/runners/new"
}


if [ "$#" -eq 3 ]; then
    INSTALL_DIR="$(cd "$1" && pwd)"
    GITHUB_VERSION="$2"
    CONFIGURE_TOKEN="$3"    
else
    usage; exit 1
fi

if [[ "$(uname)" == "Linux" ]]; then
    OS="linux-x64"
    NAME="$(hostname)"
    LABELS="sh-ubuntu_gcc_release,sh-ubuntu_clang_release,sh-ubuntu_clang_debug,sh-fedora_clang_release"
else
    OS="osx-x64"
    NAME="$(scutil --get LocalHostName)"
    LABELS="sh-macos_clang_release"
fi

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

cd "$INSTALL_DIR"

#### Clone tools
## github. For more up to date info see https://github.com/sofa-framework/sofa/settings/actions/runners/new
# know that the hash will be different for newer version of this package

# Create a folder
mkdir github-workspace && cd github-workspace
# Download the latest runner package
curl -o actions-runner-${OS}-${GITHUB_VERSION}.tar.gz -L https://github.com/actions/runner/releases/download/v${GITHUB_VERSION}/actions-runner-${OS}-${GITHUB_VERSION}.tar.gz
# Extract the installer
tar xzf ./actions-runner-${OS}-${GITHUB_VERSION}.tar.gz



## SOFA ci scripts this is normally already done on the builder to be able to launch this
#cd "$INSTALL_DIR"
#git clone https://www.github.com/bakpaul/ci.git
#cd ci 
#git checkout jenkins_gha_migration


#### Setup crontab and environment 
## crontab. No need to add a reboot action as it will be done through a job 
if [[ "$(uname)" == "Linux" ]]; then

    (crontab -l 2>/dev/null; echo "* * * * * cd \"${INSTALL_DIR}/ci\" && git pull -r") | crontab -
    (crontab -l 2>/dev/null; echo "@reboot rm -rf \"${INSTALL_DIR}/github-workspace/_work\"") | crontab -
    (crontab -l 2>/dev/null; echo "@reboot docker system prune -a -f") | crontab -
    (crontab -l 2>/dev/null; echo "@reboot \"${INSTALL_DIR}/github-workspace/run.sh\"") | crontab -
else
    if [ ! -d "~/Library/LaunchAgents/" ]; then 
        mkdir -p ~/Library/LaunchAgents/
    fi
    tempFolder=$(mktemp -d)
    cp ${SCRIPT_DIR}/*.plist ${tempFolder}/
    for filename in ${tempFolder}/*.plist; do
        sed -i '' "s/INSTALL_DIR/${INSTALL_DIR//\//\\/}/g" $filename
        mv $filename ~/Library/LaunchAgents/
    done
    launchctl enable gui/`id -u`/local.job
    rm -rf ${tempFolder}
fi

## environement
echo "ACTIONS_RUNNER_HOOK_JOB_COMPLETED=\"${INSTALL_DIR}/ci/scripts/github-hookups/post-job.sh\"" >> "${INSTALL_DIR}/github-workspace/.env"
echo "ACTIONS_RUNNER_HOOK_JOB_STARTED=\"${INSTALL_DIR}/ci/scripts/github-hookups/pre-job.sh\"" >> "${INSTALL_DIR}/github-workspace/.env"



## Final configuration
cd "$INSTALL_DIR/github-workspace"
./config.sh --unattended --url "https://github.com/bakpaul/sofa" --token "${CONFIGURE_TOKEN}" --name "${NAME}" --labels "${NAME},${LABELS}"


echo "Everything is setup in $INSTALL_DIR. Rebooting to launch the worker... "
