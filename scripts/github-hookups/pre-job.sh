#!/bin/bash

#Create folder for this run
REF_TYPE=$(echo $GITHUB_REF | awk -F '/' '{print $2}')
BRANCH_OR_PR_NUMBER=$(echo $GITHUB_REF | awk -F '/' '{print $3}')

if [ "$REF_TYPE" = "pull" ]; then
    WORK_FOLDER=$GITHUB_WORKSPACE/PR$BRANCH_OR_PR_NUMBER
else
    if [ "$GITHUB_REPOSITORY_OWNER" != "sofa-framework" ]; then
        exit 1
    else
        WORK_FOLDER=$GITHUB_WORKSPACE/$BRANCH_OR_PR_NUMBER/$GITHUB_SHA
    fi
fi


if [ ! -d  ]; then
  mkdir -p $WORK_FOLDER
fi

echo "Work folder set to $WORK_FOLDER"

