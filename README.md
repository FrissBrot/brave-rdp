# brave-rdp

Remote Brave Browser workspace for RDP/Guacamole, packaged as a small Docker Compose stack.

## Features

- Debian 12 based image with `xrdp`, `openbox`, and Brave Browser
- Audio over XRDP via `pipewire`, `pipewire-pulse`, `wireplumber`, and `pipewire-module-xrdp`
- Container-side hardening with disabled XRDP root login and `no-new-privileges`
- Guacamole-compatible network attachment via `guacamole_guac_remote`
- Managed Brave policies for privacy defaults and Bitwarden extension bootstrap
- Browser profile and cache kept out of Git

## Repository Layout

- `Dockerfile`: image build and XRDP session bootstrap
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
`BITWARDEN_BASE_URL` is injected during image build to configure the Bitwarden extension base URL.

## Run

```bash
cp .env.example .env
docker compose build
docker compose up -d
```

The service joins the external Docker network `guacamole_guac_remote`. Ensure that network exists before starting the stack.

## Hardening

- The image does not install `sudo`, and the browser user has no local privilege escalation path.
- XRDP root logins are disabled in `sesman.ini`.
- The container runs with Docker `no-new-privileges`.
- The healthcheck verifies both XRDP processes and the local RDP listener on port `3389`.

## Audio

XRDP audio redirection is enabled with PipeWire.

The image includes:

- `pipewire`
- `pipewire-pulse`
- `wireplumber`
- `pipewire-module-xrdp`
- `python3-xdg`

The session wrapper starts the PipeWire user daemons before launching Brave and explicitly loads the XRDP PipeWire module when `XRDP_SESSION=1`. `python3-xdg` is installed so Openbox can also process the Debian XDG autostart hook without errors.

## Data Handling

The repository intentionally excludes local runtime data and browser profile data:

- `data/`
- `config/`
- `vault/`

The running container stores Brave state in Docker named volumes:

- `brave_config`
- `brave_cache`
- `brave_pki`
