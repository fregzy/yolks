#!/bin/bash

# The address the game server can bind to inside the container
export INTERNAL_IP=$(ip route get 1 | awk '{print $(NF-2);exit}')

cd /home/container || exit 1

# Notice shown at the top of the console on every start. Change the text below, or override it per egg with an
# environment variable named VNDEL_NOTICE (an egg variable); set VNDEL_NOTICE to an empty value to show nothing.
NOTICE="${VNDEL_NOTICE-NOTE: Hosted by vndel — https://vndel.com}"
if [ -n "${NOTICE}" ]; then
    printf '\033[1;33m%s\033[0m\n' "${NOTICE}"
fi

# {{VARIABLE}} in the egg's startup command -> ${VARIABLE}; the shell that runs it expands the
# values from the container's environment (as plain data, never re-parsed as commands).
TEMPLATE=$(printf '%s' "${STARTUP}" | sed -e 's/{{/${/g' -e 's/}}/}/g')

exec /bin/bash -c "${TEMPLATE}"
