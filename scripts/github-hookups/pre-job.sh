#!/bin/bash

#Create folder for this run
REF_TYPE=$(echo $GITHUB_REF | awk -F '/' '{print $2}')
BRANCH_OR_PR_NUMBER=$(echo $GITHUB_REF | awk -F '/' '{print $3}')

if [ "$REF_TYPE" = "pull" ]; then
    echo "Setting env for PR #$BRANCH_OR_PR_NUMBER"
    WORK_FOLDER=$GITHUB_WORKSPACE/PR$BRANCH_OR_PR_NUMBER
else
    if [ "$GITHUB_REPOSITORY_OWNER" != "bakpaul" ]; then
        echo "This commit doesn't belong to the sofa-framework repository, exiting the job"
        exit 1
    else
        echo "Setting env for commit $(cut -c -8 <<< "$GITHUB_SHA")"
        WORK_FOLDER=$GITHUB_WORKSPACE/$BRANCH_OR_PR_NUMBER/$(cut -c -8 <<< "$GITHUB_SHA")
    fi
fi


if [ ! -d  $WORK_FOLDER ]; then
  mkdir -p $WORK_FOLDER
fi

echo $WORK_FOLDER>$GITHUB_WORKSPACE/$GITHUB_WORKFLOW_SHA

echo "Work folder set to $WORK_FOLDER"

