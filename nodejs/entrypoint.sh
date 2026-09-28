#!/bin/bash

# The address the app can bind to inside the container
INTERNAL_IP=$(ip route get 1 2>/dev/null | awk '{print $(NF-2);exit}')
export INTERNAL_IP

# Where the server files live (only overridden by the tests)
SERVER_DIR="${SERVER_DIR:-/home/container}"
cd "${SERVER_DIR}" || exit 1

# ── Notice ──────────────────────────────────────────────────────────────────────────────────────────
# Shown at the top of the console on every start. Change the text below, or override it per egg with an
# egg variable named VNDEL_NOTICE; set VNDEL_NOTICE to an empty value to show nothing.
NOTICE="${VNDEL_NOTICE-NOTE: Hosted by vndel — https://vndel.com}"
if [ -n "${NOTICE}" ]; then
    printf '\033[1;33m%s\033[0m\n' "${NOTICE}"
fi

# {{VARIABLE}} in the egg's startup command -> ${VARIABLE}; the shell that runs it expands the values from the
# container's environment (as plain data, never re-parsed as commands). An empty startup runs vndel-node.
STARTUP="${STARTUP:-vndel-node}"
TEMPLATE=$(printf '%s' "${STARTUP}" | sed -e 's/{{/${/g' -e 's/}}/}/g')

exec /bin/bash -c "${TEMPLATE}"
