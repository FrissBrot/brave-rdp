FROM debian:12

ENV DEBIAN_FRONTEND=noninteractive
ENV HOME=/home/user
ENV BROWSER_MODE=exit
ENV USER_NAME=user
ENV USER_UID=1000
ENV USER_GID=1000
ARG BITWARDEN_BASE_URL=https://vault.example.com

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
    sudo \
    curl \
    gnupg \
    procps \
    passwd \
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

RUN cat > /etc/brave/policies/managed/bitwarden.json <<'EOF'
{
  "3rdparty": {
    "extensions": {
      "nngceckbapebfimnlniiiahkandclblb": {
        "environment": {
          "base": "__BITWARDEN_BASE_URL__"
        }
      }
    }
  }
}
EOF

RUN sed -i "s|__BITWARDEN_BASE_URL__|${BITWARDEN_BASE_URL}|g" /etc/brave/policies/managed/bitwarden.json

# Benutzer anlegen
RUN groupadd -g ${USER_GID} ${USER_NAME} && \
    useradd -m -u ${USER_UID} -g ${USER_GID} -s /bin/bash ${USER_NAME} && \
    usermod -aG sudo ${USER_NAME} && \
    echo "${USER_NAME} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${USER_NAME} && \
    chmod 0440 /etc/sudoers.d/${USER_NAME}

# Browser Start Script
RUN cat > /usr/local/bin/start-browser.sh <<'EOF'
#!/bin/sh
set -eu

USER_NAME="${USER_NAME:-user}"
export HOME="/home/${USER_NAME}"
export USER="${USER_NAME}"
export LOGNAME="${USER_NAME}"

export XDG_RUNTIME_DIR="/tmp/runtime-${USER_NAME}"
export XAUTHORITY="${HOME}/.Xauthority"

PROFILE_DIR="${HOME}/.config/BraveSoftware/Brave-Browser"

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

exec brave-browser \
  --no-sandbox \
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

cleanup() {
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
RUN sed -i 's/^#\?KillDisconnected=.*/KillDisconnected=true/' /etc/xrdp/sesman.ini && \
    sed -i 's/^#\?DisconnectedTimeLimit=.*/DisconnectedTimeLimit=300/' /etc/xrdp/sesman.ini && \
    sed -i 's/^#\?IdleTimeLimit=.*/IdleTimeLimit=0/' /etc/xrdp/sesman.ini

# Container Start Script
RUN cat > /usr/local/bin/container-start.sh <<'EOF'
#!/bin/sh
set -eu

USER_NAME="${USER_NAME:-user}"
USER_PASSWORD="${USER_PASSWORD:?USER_PASSWORD environment variable must be set}"

HOME_DIR="/home/${USER_NAME}"
RUNTIME_DIR="/tmp/runtime-${USER_NAME}"

mkdir -p \
    "${HOME_DIR}/.config/BraveSoftware" \
    "${HOME_DIR}/.cache/BraveSoftware" \
    "${HOME_DIR}/.pki" \
    "${RUNTIME_DIR}" \
    /var/run/dbus \
    /var/run/xrdp

touch "${HOME_DIR}/.Xauthority"
chown -R ${USER_NAME}:${USER_NAME} "${HOME_DIR}" "${RUNTIME_DIR}"
chmod 700 "${RUNTIME_DIR}"

echo "${USER_NAME}:${USER_PASSWORD}" | chpasswd

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
