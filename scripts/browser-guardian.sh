#!/bin/sh
set -eu

USER_NAME="${USER_NAME:-user}"
export HOME="/home/${USER_NAME}"
export USER="${USER_NAME}"
export LOGNAME="${USER_NAME}"
export XDG_RUNTIME_DIR="/tmp/runtime-${USER_NAME}"
export XAUTHORITY="${HOME}/.Xauthority"

while :; do
    WINDOW_ID="$(wmctrl -lx 2>/dev/null | awk 'BEGIN { IGNORECASE = 1 } /brave/ { print $1; exit }')"

    if [ -n "${WINDOW_ID:-}" ]; then
        STATE="$(xprop -id "$WINDOW_ID" _NET_WM_STATE 2>/dev/null || true)"

        case "$STATE" in
            *_NET_WM_STATE_HIDDEN*)
                /usr/local/bin/restore-browser.sh >/dev/null 2>&1 || true
                ;;
        esac

        case "$STATE" in
            *_NET_WM_STATE_MAXIMIZED_VERT*)
                ;;
            *)
                wmctrl -ir "$WINDOW_ID" -b add,maximized_vert >/dev/null 2>&1 || true
                ;;
        esac

        case "$STATE" in
            *_NET_WM_STATE_MAXIMIZED_HORZ*)
                ;;
            *)
                wmctrl -ir "$WINDOW_ID" -b add,maximized_horz >/dev/null 2>&1 || true
                ;;
        esac
    fi

    sleep 0.5
done
