#!/bin/sh
TIMEOUT=60
ELAPSED=0

SESSION_ID=$(loginctl list-sessions --no-legend 2>/dev/null | awk '{print $1}' | head -1)
if [ -n "$SESSION_ID" ]; then
    USER_UID=$(loginctl show-session "$SESSION_ID" -p UID --value 2>/dev/null || echo "")
    if [ -n "$USER_UID" ]; then
        WAYLAND_SOCKET="/run/user/${USER_UID}/wayland-0"
        while [ ! -e "$WAYLAND_SOCKET" ] && [ $ELAPSED -lt $TIMEOUT ]; do
            sleep 1
            ELAPSED=$((ELAPSED + 1))
        done
        if [ -e "$WAYLAND_SOCKET" ]; then
            sleep 2
            exit 0
        fi
    fi
fi

ELAPSED=0
while [ -z "$(ls /run/user/*/wayland-0 2>/dev/null)" ] && [ $ELAPSED -lt $TIMEOUT ]; do
    sleep 1
    ELAPSED=$((ELAPSED + 1))
done
if [ -n "$(ls /run/user/*/wayland-0 2>/dev/null)" ]; then
    sleep 2
    exit 0
fi

echo "WARNING: Wayland socket not found after ${TIMEOUT}s"
exit 1
