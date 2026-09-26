#!/bin/bash

# The address the game server can bind to inside the container
export INTERNAL_IP=$(ip route get 1 | awk '{print $(NF-2);exit}')

cd /home/container || exit 1

# {{VARIABLE}} in the egg's startup command -> its value
PARSED=$(echo "${STARTUP}" | sed -e 's/{{/${/g' -e 's/}}/}/g' | eval echo "$(cat -)")

exec env ${PARSED}
