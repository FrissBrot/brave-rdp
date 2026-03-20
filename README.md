# brave-rdp

Remote Brave Browser workspace for RDP/Guacamole, packaged as a small Docker Compose stack.

## Features

- Debian 12 based image with `xrdp`, `xorgxrdp`, `openbox`, and Brave Browser
- Audio over XRDP via `pipewire`, `pipewire-pulse`, `wireplumber`, and `pipewire-module-xrdp`
- Container-side hardening with disabled XRDP root login, Docker `no-new-privileges`, Chromium sandbox support, and a dedicated seccomp profile
- Background window guardian that automatically restores Brave and keeps it maximized or fullscreen, depending on the selected mode
- Guacamole-compatible network attachment via `guacamole_guac_remote`
- Managed Brave policies for privacy defaults and Bitwarden extension bootstrap
- Browser state kept out of Git via one Docker named volume per container

## Repository Layout

- `Dockerfile`: image build, XRDP bootstrap, audio setup, and Brave policy configuration
- `docker-compose.yml`: service definitions for the regular Brave workspace and the WhatsApp kiosk variant
- `scripts/`: small runtime helpers for window restore and guardian behavior
- `.env.example`: required environment variables template

## Required Environment Variables

Copy `.env.example` to `.env` and adjust the values:

```env
BROWSER_MODE=restart
KIOSK_URL=
USER_PASSWORD=change-me
BITWARDEN_BASE_URL=https://vault.example.com
```

`USER_PASSWORD` is required at runtime.
`BROWSER_MODE=restart` restarts Brave inside the same XRDP session after crashes; `exit` closes the session when Brave exits.
`KIOSK_URL` is optional. If set, Brave starts as a chromeless one-page web app in fullscreen; if empty, the normal Brave workspace starts exactly as before.
`BITWARDEN_BASE_URL` is injected at container start to configure the Bitwarden extension base URL, so it is not baked into the image.

## Run

```bash
cp .env.example .env
docker compose build
docker compose up -d
```

The service joins the external Docker network `guacamole_guac_remote`. Ensure that network exists before starting the stack.

## Remote Access

By default the service is only reachable on the Docker network for Guacamole.
If you want direct RDP access on port `3389`, uncomment the `ports:` block in `docker-compose.yml`.

Login details:

- host: server IP or hostname
- port: `3389`
- username: `user`
- password: value from `.env`

## Included Services

The tracked Compose stack contains two Brave-based RDP services:

- `brave-workspace`: regular Brave workspace, optionally controlled by `KIOSK_URL`
- `brave-whatsapp`: dedicated fullscreen app instance for `https://web.whatsapp.com/`

If you want host-specific container names, volume names, or other local adjustments, keep them in an untracked `docker-compose.local.yml`.

## Kiosk / Onepager Mode

If you want the RDP session to show only a single website without tabs, address bar, or other browser chrome, set `KIOSK_URL` in `.env`:

```env
KIOSK_URL=https://example.com
```

In that mode Brave launches as an app window in fullscreen. The existing window guardian keeps the page visible and restores fullscreen if the window is minimized or loses its fullscreen state.

If `KIOSK_URL` is empty or unset, the container keeps the current default behavior and launches the regular Brave browser window.

## Hardening and Runtime Notes

- The image does not install `sudo`, and the browser user has no local privilege escalation path.
- XRDP root logins are disabled in `sesman.ini`.
- Docker `no-new-privileges` is enabled in the Compose service.
- Docker loads `seccomp/brave-seccomp.json`, which is based on the official Docker default seccomp profile and only adds the namespace syscalls Brave needs for its Chromium sandbox.
- No taskbar or helper panel is added to the session; the only intended visible app is Brave itself.
- A small background helper watches the Brave window and immediately restores it if it becomes hidden. In normal mode it keeps the window maximized; in `KIOSK_URL` mode it keeps Brave in fullscreen.
- The healthcheck verifies both XRDP processes and the local RDP listener on `127.0.0.1:3389`.

## Audio

XRDP audio redirection is enabled with PipeWire.
The session wrapper starts the PipeWire user daemons before launching Brave and explicitly loads the XRDP PipeWire module when `XRDP_SESSION=1`.
`python3-xdg` is installed so Openbox can process the Debian XDG autostart hook without errors.

## Data Handling

Each container uses exactly one Docker named volume mounted at `/workspace-data`.
At runtime the container links Brave's config, cache, and PKI paths into that single volume.
