# brave-rdp

Remote Brave Browser workspace for RDP/Guacamole, packaged as a small Docker Compose stack.

## Features

- Debian 12 based image with `xrdp`, `xorgxrdp`, `openbox`, and Brave Browser
- Audio over XRDP via `pipewire`, `pipewire-pulse`, `wireplumber`, and `pipewire-module-xrdp`
- Container-side hardening with disabled XRDP root login, Docker `no-new-privileges`, and Chromium sandbox support
- Guacamole-compatible network attachment via `guacamole_guac_remote`
- Managed Brave policies for privacy defaults and Bitwarden extension bootstrap
- Browser profile and cache kept out of Git via Docker named volumes

## Repository Layout

- `Dockerfile`: image build, XRDP bootstrap, audio setup, and Brave policy configuration
- `docker-compose.yml`: service definition and runtime configuration
- `.env.example`: required environment variables template

## Required Environment Variables

Copy `.env.example` to `.env` and adjust the values:

```env
BROWSER_MODE=restart
USER_PASSWORD=change-me
BITWARDEN_BASE_URL=https://vault.example.com
```

`USER_PASSWORD` is required at runtime.
`BROWSER_MODE=restart` restarts Brave inside the same XRDP session after crashes; `exit` closes the session when Brave exits.
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

## Hardening and Runtime Notes

- The image does not install `sudo`, and the browser user has no local privilege escalation path.
- XRDP root logins are disabled in `sesman.ini`.
- Docker `no-new-privileges` is enabled in the Compose service.
- Docker uses `seccomp=unconfined` so Brave can start with its own sandbox instead of the insecure `--no-sandbox` fallback. This is a deliberate tradeoff because Docker's default seccomp profile blocks the namespace syscalls Chromium needs.
- The healthcheck verifies both XRDP processes and the local RDP listener on `127.0.0.1:3389`.

## Audio

XRDP audio redirection is enabled with PipeWire.
The session wrapper starts the PipeWire user daemons before launching Brave and explicitly loads the XRDP PipeWire module when `XRDP_SESSION=1`.
`python3-xdg` is installed so Openbox can process the Debian XDG autostart hook without errors.

## Data Handling

The running container stores Brave state in Docker named volumes:

- `brave_config`
- `brave_cache`
- `brave_pki`
