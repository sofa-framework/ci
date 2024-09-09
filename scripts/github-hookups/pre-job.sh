#!/bin/bash

#Create folder for this run
BRANCH_NAME = $(echo $GITHUB_REF | awk -F '/' '{print $NF}')
if [ ! -d $GITHUB_WORKSPACE/$BRANCH_NAME/$GITHUB_SHA ]; then
  mkdir -p $GITHUB_WORKSPACE/$BRANCH_NAME/$GITHUB_SHA;
fi

echo $GITHUB_WORKSPACE/$BRANCH_NAME/$GITHUB_SHA > $GITHUB_WORKFLOW_SHA

