#!/bin/sh
set -eu

USER_NAME="${USER_NAME:-user}"
export HOME="/home/${USER_NAME}"
export USER="${USER_NAME}"
export LOGNAME="${USER_NAME}"
export XDG_RUNTIME_DIR="/tmp/runtime-${USER_NAME}"
export XAUTHORITY="${HOME}/.Xauthority"
KIOSK_URL="${KIOSK_URL:-}"

PROFILE_DIR="${HOME}/.config/BraveSoftware/Brave-Browser"

mkdir -p \
    "$XDG_RUNTIME_DIR" \
    "$PROFILE_DIR" \
    "${HOME}/.cache/BraveSoftware" \
    "${HOME}/.pki"

touch "$XAUTHORITY"
chmod 700 "$XDG_RUNTIME_DIR"

WINDOW_ID="$(wmctrl -lx 2>/dev/null | awk 'BEGIN { IGNORECASE = 1 } /brave/ { print $1; exit }')"

if [ -n "${WINDOW_ID:-}" ]; then
    wmctrl -ir "$WINDOW_ID" -b remove,hidden >/dev/null 2>&1 || true
    if [ -n "$KIOSK_URL" ]; then
        wmctrl -ir "$WINDOW_ID" -b add,fullscreen,maximized_vert,maximized_horz >/dev/null 2>&1 || true
    else
        wmctrl -ir "$WINDOW_ID" -b add,maximized_vert,maximized_horz >/dev/null 2>&1 || true
    fi
    wmctrl -ia "$WINDOW_ID" >/dev/null 2>&1 || true
    exit 0
fi

/usr/local/bin/start-browser.sh >/dev/null 2>&1 &
