#!/bin/bash

# The address the app can bind to inside the container
INTERNAL_IP=$(ip route get 1 2>/dev/null | awk '{print $(NF-2);exit}')
export INTERNAL_IP

# Where the server files live (only overridden by the tests)
SERVER_DIR="${SERVER_DIR:-/home/container}"
cd "${SERVER_DIR}" || exit 1

# ── A name for the uid ──────────────────────────────────────────────────────────────────────────────
# Wings runs the container as its own uid, which /etc/passwd does not list: then os.userInfo() and whoami fail
# (tsx and other tools stop on it). nss_wrapper answers for that uid from files in /tmp instead — /etc/passwd itself
# stays read-only (a writable one would let anyone add a root user).
NSS_LIB="${NSS_WRAPPER_LIB:-/usr/lib/x86_64-linux-gnu/libnss_wrapper.so}"
if ! whoami >/dev/null 2>&1 && [ -f "${NSS_LIB}" ]; then
    # only when every file was written: a half-made passwd file would be worse than none
    if NSS_DIR="$(mktemp -d 2>/dev/null)" \
        && cp /etc/passwd "${NSS_DIR}/passwd" \
        && printf 'container:x:%s:%s:container:%s:/bin/bash\n' "$(id -u)" "$(id -g)" "${HOME:-/home/container}" >> "${NSS_DIR}/passwd" \
        && cp /etc/group "${NSS_DIR}/group" \
        && { getent group "$(id -g)" >/dev/null 2>&1 || printf 'container:x:%s:\n' "$(id -g)" >> "${NSS_DIR}/group"; }; then
        export NSS_WRAPPER_PASSWD="${NSS_DIR}/passwd" NSS_WRAPPER_GROUP="${NSS_DIR}/group"
        export LD_PRELOAD="${NSS_LIB}${LD_PRELOAD:+ ${LD_PRELOAD}}"
    fi
fi

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
