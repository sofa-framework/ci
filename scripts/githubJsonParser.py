#!/usr/bin/python

import json;

def get_commit_message(json_string):
    obj=json.load(json_string)
    print obj['commit']['message']

def get_commit_author(json_string):
    obj=json.load(json_string)
    print obj['commit']['author']['name']

def get_commit_date(json_string):
    obj=json.load(json_string)
    commit_date=obj['commit']['committer']['date']
    dt=datetime.datetime.strptime(str(commit_date), '%Y-%m-%dT%H:%M:%SZ')
    timestamp=(dt-datetime.datetime(1970,1,1)).total_seconds()
    print int(timestamp);