#!/bin/bash

# The address the game server can bind to inside the container
export INTERNAL_IP=$(ip route get 1 | awk '{print $(NF-2);exit}')

cd /home/container || exit 1

# {{VARIABLE}} in the egg's startup command -> ${VARIABLE}; the shell that runs it expands the
# values from the container's environment (as plain data, never re-parsed as commands).
TEMPLATE=$(printf '%s' "${STARTUP}" | sed -e 's/{{/${/g' -e 's/}}/}/g')

exec /bin/bash -c "${TEMPLATE}"
