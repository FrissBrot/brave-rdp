FROM debian:12

ENV DEBIAN_FRONTEND=noninteractive
ENV HOME=/home/user
ENV BROWSER_MODE=exit
ENV BROWSER_DATA_DIR=/workspace-data
ENV KIOSK_URL=
ENV USER_NAME=user
ENV USER_UID=1000
ENV USER_GID=1000

RUN echo "deb http://deb.debian.org/debian bookworm-backports main" > /etc/apt/sources.list.d/bookworm-backports.list && \
    apt-get update && apt-get install -y \
    xrdp \
    openbox \
    python3-xdg \
    dbus-x11 \
    xorgxrdp \
    alsa-utils \
    pulseaudio-utils \
    xterm \
    ca-certificates \
    curl \
    gnupg \
    procps \
    passwd \
    wmctrl \
    tini \
    && apt-get install -y -t bookworm-backports \
    pipewire \
    pipewire-pulse \
    wireplumber \
    pipewire-module-xrdp \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Brave Repository
RUN curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg \
    https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg] https://brave-browser-apt-release.s3.brave.com/ stable main" \
    > /etc/apt/sources.list.d/brave-browser-release.list

# Brave installieren
RUN apt-get update && apt-get install -y \
    brave-browser \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Brave Policies
RUN mkdir -p /etc/brave/policies/managed && \
    cat > /etc/brave/policies/managed/managed_policies.json <<'EOF'
{
  "DefaultSearchProviderEnabled": true,
  "DefaultSearchProviderName": "Startpage",
  "DefaultSearchProviderKeyword": "startpage.com",
  "DefaultSearchProviderSearchURL": "https://www.startpage.com/sp/search?query={searchTerms}",
  "DefaultSearchProviderSuggestURL": "https://www.startpage.com/suggestions?q={searchTerms}",

  "BraveWalletDisabled": true,
  "BraveRewardsDisabled": true,
  "BraveVPNDisabled": true,
  "BraveNewsDisabled": true,
  "TorDisabled": true,
  "BraveAIChatEnabled": false,

  "MetricsReportingEnabled": false,
  "PromotionalTabsEnabled": false,
  "ShowRecommendationsEnabled": false,
  "BrowserSignin": 0,
  "SyncDisabled": true,

  "PasswordManagerEnabled": false,
  "AutofillAddressEnabled": false,
  "AutofillCreditCardEnabled": false,

  "ExtensionInstallForcelist": [
    "nngceckbapebfimnlniiiahkandclblb;https://clients2.google.com/service/update2/crx"
  ]
}
EOF

RUN mkdir -p /etc/brave/policies/recommended && \
    cat > /etc/brave/policies/recommended/color.json <<'EOF'
{
  "BrowserThemeColor": "#008000"
}
EOF

# Benutzer anlegen
RUN groupadd -g ${USER_GID} ${USER_NAME} && \
    useradd -m -u ${USER_UID} -g ${USER_GID} -s /bin/bash ${USER_NAME}

COPY scripts/restore-browser.sh /usr/local/bin/restore-browser.sh
COPY scripts/browser-guardian.sh /usr/local/bin/browser-guardian.sh

RUN chmod 755 /usr/local/bin/restore-browser.sh /usr/local/bin/browser-guardian.sh

# Shared session env loader for XRDP sessions
RUN cat > /usr/local/bin/load-session-env.sh <<'EOF'
#!/bin/sh
set -eu

SESSION_ENV_FILE="/usr/local/etc/brave-session.env"

if [ -f "$SESSION_ENV_FILE" ]; then
    # shellcheck disable=SC1091
    . "$SESSION_ENV_FILE"
fi

export BROWSER_MODE="${BROWSER_MODE:-}"
export BROWSER_DATA_DIR="${BROWSER_DATA_DIR:-/workspace-data}"
export BITWARDEN_BASE_URL="${BITWARDEN_BASE_URL:-https://vault.example.com}"
export KIOSK_URL="${KIOSK_URL:-}"
EOF

RUN chmod +x /usr/local/bin/load-session-env.sh

# Browser Start Script
RUN cat > /usr/local/bin/start-browser.sh <<'EOF'
#!/bin/sh
set -eu

. /usr/local/bin/load-session-env.sh

USER_NAME="${USER_NAME:-user}"
export HOME="/home/${USER_NAME}"
export USER="${USER_NAME}"
export LOGNAME="${USER_NAME}"

export XDG_RUNTIME_DIR="/tmp/runtime-${USER_NAME}"
export XAUTHORITY="${HOME}/.Xauthority"

PROFILE_DIR="${HOME}/.config/BraveSoftware/Brave-Browser"
KIOSK_URL="${KIOSK_URL:-}"

mkdir -p \
    "$XDG_RUNTIME_DIR" \
    "$PROFILE_DIR" \
    "${HOME}/.cache/BraveSoftware" \
    "${HOME}/.pki"

touch "$XAUTHORITY"
chmod 700 "$XDG_RUNTIME_DIR"

rm -f "$PROFILE_DIR/SingletonLock" \
      "$PROFILE_DIR/SingletonSocket" \
      "$PROFILE_DIR/SingletonCookie"

if [ -n "$KIOSK_URL" ]; then
    exec brave-browser \
      --no-first-run \
      --no-default-browser-check \
      --app="$KIOSK_URL" \
      --start-fullscreen \
      --user-data-dir="$PROFILE_DIR"
fi

exec brave-browser \
  --no-first-run \
  --no-default-browser-check \
  --start-maximized \
  --user-data-dir="$PROFILE_DIR"
EOF

RUN chmod +x /usr/local/bin/start-browser.sh

# Audio Session Start Script
RUN cat > /usr/local/bin/start-audio.sh <<'EOF'
#!/bin/sh
set -eu

USER_NAME="${USER_NAME:-user}"
export HOME="/home/${USER_NAME}"
export USER="${USER_NAME}"
export LOGNAME="${USER_NAME}"
export XDG_RUNTIME_DIR="/tmp/runtime-${USER_NAME}"
export XDG_STATE_HOME="${HOME}/.local/state"
AUDIO_LOG="${HOME}/pipewire-xrdp.log"

mkdir -p \
  "${XDG_RUNTIME_DIR}" \
  "${HOME}/.config/pipewire" \
  "${HOME}/.config/pulse" \
  "${XDG_STATE_HOME}/wireplumber"
chmod 700 "${XDG_RUNTIME_DIR}"

: > "${AUDIO_LOG}"
echo "XRDP_SESSION=${XRDP_SESSION:-}" >> "${AUDIO_LOG}"
echo "XRDP_SOCKET_PATH=${XRDP_SOCKET_PATH:-}" >> "${AUDIO_LOG}"

if ! pgrep -u "$(id -u)" -x pipewire >/dev/null 2>&1; then
    pipewire >"${HOME}/pipewire.log" 2>&1 &
fi

if ! pgrep -u "$(id -u)" -x wireplumber >/dev/null 2>&1; then
    wireplumber >"${HOME}/wireplumber.log" 2>&1 &
fi

if ! pgrep -u "$(id -u)" -x pipewire-pulse >/dev/null 2>&1; then
    pipewire-pulse >"${HOME}/pipewire-pulse.log" 2>&1 &
fi

for _ in 1 2 3 4 5; do
    if pactl info >/dev/null 2>&1; then
        break
    fi
    sleep 1
done

if ! pactl info >/dev/null 2>&1; then
    echo "PipeWire/PulseAudio compatibility layer did not become ready" >&2
    exit 1
fi

if [ "${XRDP_SESSION:-0}" = "1" ] && [ -n "${XRDP_SOCKET_PATH:-}" ]; then
    /usr/libexec/pipewire-module-xrdp/load_pw_modules.sh >>"${AUDIO_LOG}" 2>&1

    for _ in 1 2 3 4 5; do
        if pactl list short sinks 2>/dev/null | grep -q 'xrdp-sink'; then
            exit 0
        fi
        sleep 1
    done

    echo "xrdp-sink was not created" >> "${AUDIO_LOG}"
    pactl list short sinks >> "${AUDIO_LOG}" 2>&1 || true
    exit 1
fi

exit 0
EOF

RUN chmod +x /usr/local/bin/start-audio.sh

# XRDP/Openbox Session Wrapper:
# startet Openbox, startet dann Brave im Vordergrund
# und beendet die Session, sobald Brave geschlossen wird
RUN cat > /usr/local/bin/rdp-session.sh <<'EOF'
#!/bin/sh
set -eu

. /usr/local/bin/load-session-env.sh

USER_NAME="${USER_NAME:-user}"
export HOME="/home/${USER_NAME}"
export USER="${USER_NAME}"
export LOGNAME="${USER_NAME}"

export XDG_RUNTIME_DIR="/tmp/runtime-${USER_NAME}"
export XAUTHORITY="${HOME}/.Xauthority"

mkdir -p "$XDG_RUNTIME_DIR"
touch "$XAUTHORITY"
chmod 700 "$XDG_RUNTIME_DIR"

openbox-session &
OPENBOX_PID=$!
/usr/local/bin/browser-guardian.sh &
GUARDIAN_PID=$!

cleanup() {
    kill -TERM "$GUARDIAN_PID" 2>/dev/null || true
    wait "$GUARDIAN_PID" 2>/dev/null || true
    openbox --exit >/dev/null 2>&1 || true
    kill -TERM "$OPENBOX_PID" 2>/dev/null || true
    wait "$OPENBOX_PID" 2>/dev/null || true
}

trap cleanup EXIT INT TERM

/usr/local/bin/start-audio.sh >> "${HOME}/pulse-start.log" 2>&1
/usr/local/bin/start-browser.sh >> "${HOME}/browser-start.log" 2>&1
BROWSER_RC=$?

cleanup
exit "$BROWSER_RC"
EOF

RUN chmod +x /usr/local/bin/rdp-session.sh

# XRDP Session über eigenes Wrapper-Script
RUN cat > /etc/skel/.xsession <<'EOF'
#!/bin/sh
exec dbus-launch --exit-with-session /usr/local/bin/rdp-session.sh
EOF

RUN cp /etc/skel/.xsession /home/${USER_NAME}/.xsession && \
    chown ${USER_NAME}:${USER_NAME} /home/${USER_NAME}/.xsession && \
    chmod 755 /etc/skel/.xsession /home/${USER_NAME}/.xsession

# XRDP Optimierungen
RUN sed -i 's/^max_bpp=.*/max_bpp=16/' /etc/xrdp/xrdp.ini || true && \
    sed -i 's/^#\?use_fastpath=.*/use_fastpath=both/' /etc/xrdp/xrdp.ini || true && \
    grep -q '^tcp_nodelay=' /etc/xrdp/xrdp.ini || printf '\ntcp_nodelay=true\n' >> /etc/xrdp/xrdp.ini && \
    grep -q '^tcp_keepalive=' /etc/xrdp/xrdp.ini || printf 'tcp_keepalive=true\n' >> /etc/xrdp/xrdp.ini

# XRDP Session Timeout
RUN sed -i 's/^#\?AllowRootLogin=.*/AllowRootLogin=false/' /etc/xrdp/sesman.ini && \
    sed -i 's/^#\?KillDisconnected=.*/KillDisconnected=true/' /etc/xrdp/sesman.ini && \
    sed -i 's/^#\?DisconnectedTimeLimit=.*/DisconnectedTimeLimit=300/' /etc/xrdp/sesman.ini && \
    sed -i 's/^#\?IdleTimeLimit=.*/IdleTimeLimit=0/' /etc/xrdp/sesman.ini

# Container Start Script
RUN cat > /usr/local/bin/container-start.sh <<'EOF'
#!/bin/sh
set -eu

USER_NAME="${USER_NAME:-user}"
USER_PASSWORD="${USER_PASSWORD:?USER_PASSWORD environment variable must be set}"
BITWARDEN_BASE_URL="${BITWARDEN_BASE_URL:-https://vault.example.com}"
BROWSER_DATA_DIR="${BROWSER_DATA_DIR:-/workspace-data}"
KIOSK_URL="${KIOSK_URL:-}"

HOME_DIR="/home/${USER_NAME}"
RUNTIME_DIR="/tmp/runtime-${USER_NAME}"
SESSION_ENV_FILE="/usr/local/etc/brave-session.env"

mkdir -p \
    "${HOME_DIR}/.config" \
    "${HOME_DIR}/.cache" \
    "${BROWSER_DATA_DIR}/.config/BraveSoftware" \
    "${BROWSER_DATA_DIR}/.cache/BraveSoftware" \
    "${BROWSER_DATA_DIR}/.pki" \
    "${RUNTIME_DIR}" \
    /usr/local/etc \
    /var/run/dbus \
    /var/run/xrdp

rm -rf \
    "${HOME_DIR}/.config/BraveSoftware" \
    "${HOME_DIR}/.cache/BraveSoftware" \
    "${HOME_DIR}/.pki"

ln -s "${BROWSER_DATA_DIR}/.config/BraveSoftware" "${HOME_DIR}/.config/BraveSoftware"
ln -s "${BROWSER_DATA_DIR}/.cache/BraveSoftware" "${HOME_DIR}/.cache/BraveSoftware"
ln -s "${BROWSER_DATA_DIR}/.pki" "${HOME_DIR}/.pki"

quote_shell_value() {
    printf "%s" "$1" | sed "s/'/'\\\\''/g"
}

{
    printf "BROWSER_MODE='%s'\n" "$(quote_shell_value "${BROWSER_MODE}")"
    printf "BROWSER_DATA_DIR='%s'\n" "$(quote_shell_value "${BROWSER_DATA_DIR}")"
    printf "BITWARDEN_BASE_URL='%s'\n" "$(quote_shell_value "${BITWARDEN_BASE_URL}")"
    printf "KIOSK_URL='%s'\n" "$(quote_shell_value "${KIOSK_URL}")"
    printf "export BROWSER_MODE BROWSER_DATA_DIR BITWARDEN_BASE_URL KIOSK_URL\n"
} > "${SESSION_ENV_FILE}"

touch "${HOME_DIR}/.Xauthority"
chown -R ${USER_NAME}:${USER_NAME} "${HOME_DIR}" "${RUNTIME_DIR}" "${BROWSER_DATA_DIR}"
chmod 700 "${RUNTIME_DIR}"
chmod 644 "${SESSION_ENV_FILE}"

echo "${USER_NAME}:${USER_PASSWORD}" | chpasswd

cat > /etc/brave/policies/managed/bitwarden.json <<POLICY
{
  "3rdparty": {
    "extensions": {
      "nngceckbapebfimnlniiiahkandclblb": {
        "environment": {
          "base": "${BITWARDEN_BASE_URL}"
        }
      }
    }
  }
}
POLICY

rm -f /var/run/xrdp/xrdp-sesman.pid /var/run/xrdp/xrdp.pid

if [ ! -f /run/dbus/pid ]; then
    service dbus start
fi

/usr/sbin/xrdp-sesman --nodaemon &
SES_PID=$!

/usr/sbin/xrdp --nodaemon &
XRDP_PID=$!

term_handler() {
    kill -TERM "$SES_PID" "$XRDP_PID" 2>/dev/null || true
    wait "$SES_PID" 2>/dev/null || true
    wait "$XRDP_PID" 2>/dev/null || true
    exit 0
}

trap term_handler INT TERM

while true; do
    if ! kill -0 "$SES_PID" 2>/dev/null; then
        echo "xrdp-sesman beendet"
        kill -TERM "$XRDP_PID" 2>/dev/null || true
        wait "$XRDP_PID" 2>/dev/null || true
        exit 1
    fi

    if ! kill -0 "$XRDP_PID" 2>/dev/null; then
        echo "xrdp beendet"
        kill -TERM "$SES_PID" 2>/dev/null || true
        wait "$SES_PID" 2>/dev/null || true
        exit 1
    fi

    sleep 2
done
EOF

RUN chmod +x /usr/local/bin/container-start.sh

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD pgrep -x xrdp >/dev/null && pgrep -x xrdp-sesman >/dev/null || exit 1

EXPOSE 3389

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["/usr/local/bin/container-start.sh"]
