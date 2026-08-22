# Hermes Agent stack

Runs the official [Nous Research Hermes Agent](https://hermes-agent.nousresearch.com/docs/user-guide/docker) gateway and built-in dashboard alongside the community [Hermes WebUI](https://github.com/nesquena/hermes-webui/blob/master/docs/docker.md). The layout follows the WebUI project's maintained two-container deployment model and supports Docker and Podman 4+.

## Services

| Service | URL | Authentication |
| --- | --- | --- |
| Hermes WebUI | `https://hermes.${DOMAIN_NAME}` | `HERMES_WEBUI_PASSWORD` |
| Hermes dashboard | `https://hermes-dashboard.${DOMAIN_NAME}` | `HERMES_DASHBOARD_USERNAME` and `HERMES_DASHBOARD_PASSWORD` |
| Hermes gateway API | `https://hermes-gateway.${DOMAIN_NAME}` | Bearer token from `HERMES_API_SERVER_KEY` |
| Hermes desktop | RDP to `${HERMES_RDP_BIND_ADDRESS}:3389` | Tailscale network access |

No service publishes a host port. The WebUI, dashboard, and gateway are reachable only through the existing Traefik `proxy` network. The WebUI uses the gateway runs API so approval prompts work, while the Agent and WebUI share Hermes configuration, sessions, memories, and skills through `hermes_home`.

These routes use the private `websecure` entrypoint, not the public `pubsecure` entrypoint. The gateway still has authenticated remote command execution capabilities; keep the private entrypoint limited to trusted networks or Tailscale.

Hermes WebUI is an independent community project, not an official Nous Research component.

## First-time setup

Add strong, unique secrets to the repository root `.env`:

```shell
HERMES_API_SERVER_KEY=paste-output-of-openssl-rand-hex-32
HERMES_WEBUI_PASSWORD=replace-with-a-strong-password
HERMES_DASHBOARD_USERNAME=admin
HERMES_DASHBOARD_PASSWORD=replace-with-another-strong-password
HERMES_DASHBOARD_SECRET=paste-output-of-openssl-rand-base64-32
HERMES_RDP_BIND_ADDRESS=100.x.y.z
HERMES_CHROME_PROXY_URL=
```

Generate the API key with `openssl rand -hex 32` and the dashboard signing secret with `openssl rand -base64 32`, then save their output; `.env` files do not evaluate shell substitutions.

Set `HERMES_RDP_BIND_ADDRESS` to the target host's Tailscale IPv4 address from `tailscale ip -4`. Compose refuses to start without it so Weston RDP cannot accidentally bind every host interface. `HERMES_CHROME_PROXY_URL` is optional and accepts a Chromium-supported proxy URL without embedded credentials.

Run the interactive setup before starting the stack:

```shell
make setup
make deploy
```

The setup wizard writes model credentials, messaging tokens, and configuration to the persistent volume. Configure at least one model provider. Messaging integrations are optional when using the WebUI.

`make setup` is only for initial setup before deployment. It uses `compose run`, which creates another container mounted to `hermes_home`; never run it while the persistent gateway is active. For later reconfiguration, use the existing container so there is only one writer:

```shell
docker exec hermes-agent hermes gateway stop
docker exec -it hermes-agent hermes setup
docker exec hermes-agent hermes gateway start
```

Use `podman exec` instead when deployed with Podman.

For Nous Portal authentication during initial setup, run this before `make deploy`:

```shell
docker-compose run --rm hermes-agent setup --portal
```

For an unattended gateway, the official documentation recommends enabling `tool_loop_guardrails.hard_stop_enabled` in the generated Hermes `config.yaml`.

## Deployment

On the target machine, either use this repository's user service or run Compose directly:

```shell
systemctl --user enable --now docker-compose@hermes.service
```

```shell
podman compose --env-file ../../.env up -d
```

The images support `linux/amd64` and `linux/arm64`. Named volumes avoid host-path ownership assumptions. Podman 4 or newer is required for reliable sharing between the gateway and WebUI containers.

The derived Agent image adds Weston, XWayland, Chromium, AT-SPI, and Cua Driver. Weston presents a persistent 1920x1080 desktop over TLS-enabled RDP, while Chromium runs visibly through XWayland with its profile under `hermes_home`. CDP listens only on container loopback and is never published through Compose or Traefik. Chromium uses `--no-sandbox` because Docker's default seccomp profile blocks its namespace sandbox; the alternative would require the broader `SYS_ADMIN` capability. RDP has no application-level login, so keep the configured Tailscale address and tailnet ACL restricted to trusted devices.

After deployment, connect an RDP client to `${HERMES_RDP_BIND_ADDRESS}:3389`, accept the self-signed certificate, and verify Computer Use:

```shell
make computer-use-doctor
```

Enable the `computer_use` toolset with `hermes tools` or the dashboard. The default Cua permission mode is `standard`; do not enable YOLO mode for an unattended gateway. Attaching to Chromium's existing persistent profile additionally requires `computer_use.grant_existing_profile: true` in Hermes `config.yaml`. Driver-owned isolated browser profiles do not require that grant.

To use the Makefile explicitly with Podman:

```shell
make setup COMPOSE='podman compose'
make deploy COMPOSE='podman compose'
```

Create DNS entries for `hermes.${DOMAIN_NAME}`, `hermes-dashboard.${DOMAIN_NAME}`, and `hermes-gateway.${DOMAIN_NAME}` pointing to the target machine before deployment.

## Administration

```shell
make logs
make version
docker exec hermes-agent hermes status
curl -H "Authorization: Bearer ${HERMES_API_SERVER_KEY}" https://hermes-gateway.${DOMAIN_NAME}/health/detailed
```

With Podman, replace `docker` with `podman`. Do not run a second gateway against the same `hermes_home` volume; Hermes state does not support concurrent writers.

## Upgrades

The shared `hermes_agent_src` volume copies `/opt/hermes` from the agent image on first creation. It must be recreated when changing the agent image tag, while `hermes_home` must remain intact:

```shell
podman compose down
podman volume rm hermes_hermes_agent_src
podman compose pull
podman compose build --pull hermes-agent
podman compose up -d
```

Upgrade the gateway and WebUI together. The WebUI currently imports Hermes internals, so mismatched release trains are not supported. Never remove `hermes_hermes_home`; it contains all persistent agent state.

The stack intentionally pins Agent `v2026.8.19`, WebUI `0.52.261`, and Cua Driver `0.20.0`. This exact Agent/WebUI pair was tested from fresh volumes: the WebUI stages the read-only Agent source before performing its editable install, starts successfully, and remains running. Earlier WebUI releases can restart-loop against Agent 0.20 because of the packaging regression tracked in [WebUI issue #6441](https://github.com/nesquena/hermes-webui/issues/6441). Test future upgrades as an exact three-component set before changing these pins.
