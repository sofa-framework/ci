#!/bin/bash

vm-is-windows() {
    if [[ "$(uname)" != "Darwin" && "$(uname)" != "Linux" ]]; then
        return 0 # true
    else
        return 1 # false
    fi
}

in-array() {
    IFS=' ' read -ra array <<< "$2"
    for e in "${array[@]}"; do   
        if [[ "$e" == "$1" ]]; then
            return 0; 
        fi
    done
    return 1
}
