#!/bin/bash

# The address the game server can bind to inside the container
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
# container's environment (as plain data, never re-parsed as commands).
TEMPLATE=$(printf '%s' "${STARTUP}" | sed -e 's/{{/${/g' -e 's/}}/}/g')

# ── Friendly checks (they only print; the server is never blocked by a warning) ─────────────────────
if [[ "${TEMPLATE}" == *"./mta-server64"* ]]; then
    if [ ! -f ./mta-server64 ]; then
        printf '\033[1;31m%s\033[0m\n' "ERROR: ./mta-server64 was not found in the server folder. Reinstall the server, or check the START command."
        exit 1
    fi
    # The game binary must be executable (instead of "chmod 777 *" on every start)
    [ -x ./mta-server64 ] || chmod u+x ./mta-server64 2>/dev/null

    # Missing system libraries are the most common reason MTA modules (e.g. MySQL) fail to load: say which ones
    missing=$(for f in ./mta-server64 ./x64/*.so; do [ -f "$f" ] && ldd "$f" 2>/dev/null | grep "not found"; done | sed 's/^[[:space:]]*//' | sort -u)
    if [ -n "${missing}" ]; then
        printf '\033[1;33m%s\033[0m\n' "WARNING: missing system libraries (some MTA modules may not load):"
        printf '%s\n' "${missing}"
    fi
fi

exec /bin/bash -c "${TEMPLATE}"
