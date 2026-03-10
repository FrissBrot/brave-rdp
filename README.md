# brave-rdp

Remote Brave Browser workspace for RDP/Guacamole, packaged as a small Docker Compose stack.

## Features

- Debian 12 based image with `xrdp`, `openbox`, and Brave Browser
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

## Data Handling

The repository intentionally excludes local runtime data and browser profile data:

- `data/`
- `config/`
- `vault/`

The running container stores Brave state in Docker named volumes:

- `brave_config`
- `brave_cache`
- `brave_pki`
