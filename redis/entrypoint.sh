#!/bin/bash
# Pelican starts this image with the egg's Startup command in $STARTUP, with {{VARIABLE}} placeholders.
cd /home/container || exit 1

if [ -z "${STARTUP:-}" ]; then
    echo "[vndel] STARTUP is empty: set the egg's Startup command."
    exit 1
fi

MODIFIED_STARTUP=$(printf '%s' "${STARTUP}" | sed -e 's/{{/${/g' -e 's/}}/}/g')
echo ":/home/container$ ${MODIFIED_STARTUP}"

# exec: redis-server becomes the main process, so the panel's Stop (Ctrl+C) reaches it and it saves before it exits
eval "exec ${MODIFIED_STARTUP}"
