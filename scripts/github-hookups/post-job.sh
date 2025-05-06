#!/bin/bash
if [ "$RUNNER_OS" = "Windows" ]; then
	#Delete simlink
	echo "Deleting simlink '/c/sl-gha' to reduce path length problem on Windows"
	cmd //c "rmdir C:\sl-gha" > /dev/null
fi