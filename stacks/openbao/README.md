# OpenBao Authorizer

Homelab deployment for OpenBao Authorizer, its pinned OpenBao server, and
`openbao-plugin-secrets-github`.

## Components

- `openbao`: a thin image based on OpenBao `v2.7.1` that
  contains only the SHA-256-verified GitHub secrets plugin `v0.1.2`, auto-unseals
  with a host-held static key, and is exposed through Traefik at
  `https://bao.${DOMAIN_NAME}`.
- `authorizer`: `ghcr.io/xtruder/openbao-authorizer`, exposed through the shared
  Traefik `proxy` network at `https://baoauthz.${DOMAIN_NAME}`.

The OpenBao container keeps its upstream/native entrypoint and starts sealed.
Initialization, plugin registration, and policy reconciliation happen
**only** through explicit operator scripts. These scripts load `.env` (or `ENV`),
run disposable Bao CLI containers joined to the server container's network
namespace, and never execute Bao inside the server container. `make initialize`
initializes once and writes one recovery share and the initial root token to
ignored `runtime/init.json` at mode
`0600`; `make setup` performs the separate
write-only reconciliation. Container restarts apply neither operation.

## Configuration and secrets

Tracked files contain no passwords, tokens, or private keys. Run the interactive
wizard on the target host:

```sh
make configure
```

The stack requires the `podman-compose` provider directly; `podman compose` may
delegate to Docker Compose, which rejects native external Podman secrets.

The wizard writes only non-secret deployment values to ignored `.env`. It
creates these rootless Podman secrets directly without writing their contents
beside the Compose file:

- `openbao_static_seal_key`: generated 32-byte static seal key.
- `authorizer_encryption_key`: generated base64 encoding of 32 bytes.
- `admin_password`: generated password for the full-access `admin` user.
- `approver_password`: generated password for the approval-only `approver` user.
- `agent_password`: generated password for the host `agent` user.
- `github_app_private_key`: pasted GitHub App PEM private key.
- `vapid_public_key` and `vapid_private_key`: generated P-256 Web Push keys.
- `openbao_authorizer_token`: initial placeholder replaced during `make setup`.

`make setup` creates or replaces the generated `openbao_authorizer_token` Podman
secret after OpenBao issues the token. The token expires after 30 days and is not
renewed, so rerun `make setup && make start` before then. Setup also writes
`runtime/agent-token` for host-side `bao-cred`, and `runtime/opencode-role-id` and
`runtime/opencode-secret-id` for the opencode plugin. `runtime/init.json` contains the initial root token and
single recovery share. Secret backup and recovery policy are operator-owned.

`make setup` reconciles:

- `userpass` users `admin` (full OpenBao administration) and `approver` (member
  of `homelab-approvers`, which carries `openbao-authorizer-approver`).
- OpenBao CORS for `https://baoauthz.${DOMAIN_NAME}`, because approvers sign in
  to OpenBao directly from the PWA.
- The `opencode-session` token role and the `opencode-minter` AppRole on
  `approle/`, which the opencode plugin uses to mint one Session Token per
  opencode session.
- The `agent` user on the separate `agents/` userpass mount. Its tokens start
  with no secret access; the authorizer's `host-agent` Requester Rule matches
  every token from that mount, so don't add other users to it.

Agents get access only through Grants that an approver approves in the PWA.
Grantable paths are limited to `github/token/project-*` (see `authorizer.hcl`).

Retrieve a generated login password only when needed:

```sh
podman secret inspect --showsecret --format '{{.SecretData}}' admin_password
podman secret inspect --showsecret --format '{{.SecretData}}' approver_password
```

The account-specific installation IDs, account names, repository selectors, and
permission profiles remain tracked in `permission-sets.json`.

### GitHub App

The wizard opens GitHub's app registration page. Create a private app, disable
webhooks, and grant at least the repository permissions requested by the
profiles in `permission-sets.json`. After creating it:

1. Copy its numeric App ID into the wizard.
2. Generate one private key and paste the downloaded PEM into the wizard.
3. Install the app on every account named in `permission-sets.json` and select
   the repositories it may access.
4. Copy each installation ID into the corresponding `installation_id` field.

The GitHub App's granted permissions are an upper bound: a generated installation
token cannot receive a permission that the app installation itself lacks.

### Web Push and Mozilla

VAPID keys are generated locally by the wizard; Mozilla does not issue an API
key or require a separate developer account. When Firefox subscribes over the
HTTPS authorizer origin, it supplies its Mozilla Push endpoint automatically.
`authorizer.hcl` allows `updates.push.services.mozilla.com`; it also allows
`ntfy.sh` for Fennec installations using an ntfy UnifiedPush distributor. The
configured VAPID subject must be a `mailto:` contact or HTTPS URL.

## Deploy

Then deploy and explicitly configure it:

```sh
make configure # interactive .env and Podman secret setup
make validate
make deploy   # builds the plugin image and starts OpenBao sealed
make initialize # explicit init/unseal operation
make setup    # explicit plugin/policy/user/GitHub reconciliation
make start    # recreates the authorizer with the current Podman secrets
make status
```

After an OpenBao container or host restart, it auto-unseals from the mounted
static key; run `make start` if the authorizer is not already running. `make
setup` is the only operation that changes OpenBao policies and plugin
configuration.

## Login

OpenBao's UI is available at `https://bao.${DOMAIN_NAME}/ui/`. Prefer the
`userpass` method with username `admin`; print its generated password only when
needed:

```sh
podman secret inspect --showsecret --format '{{.SecretData}}' admin_password
```

The initial root token can also log into OpenBao and can be printed with:

```sh
jq -r '.root_token' runtime/init.json
```

Use the root token only for recovery/bootstrap operations. At
`https://baoauthz.${DOMAIN_NAME}`, sign in with username `approver`; the browser
sends the password to OpenBao, never to the authorizer:

```sh
podman secret inspect --showsecret --format '{{.SecretData}}' approver_password
```

For local image testing, set this in `.env`:

```dotenv
AUTHORIZER_IMAGE=openbao-authorizer:test
```

## Approval-gated GitHub CLI

The stack writes a token for the `agent` user to ignored `runtime/agent-token`
(valid 30 days). To get a new one anywhere, log in with the `agent_password`
Podman secret:

```sh
export BAO_ADDR=https://bao.cloud.x-truder.net OPENBAO_AUTHORIZER_URL=https://baoauthz.cloud.x-truder.net
bao login -method=userpass -path=agents username=agent
export BAO_TOKEN="$(bao print token)"
```

Install `bao-cred`, then use:

```sh
BAO_TOKEN="$(cat runtime/agent-token)" bao-cred read --reason "inspect the authorizer repo" \
  --map GH_TOKEN=token github/token/project-authorizer -- \
  gh repo view xtruder/openbao-authorizer
```

On permission denied, `bao-cred` files a Grant Request, waits for approval in
the PWA, retries the read, and exports `GH_TOKEN` only to the child `gh` process.

## opencode

Copy `runtime/opencode-role-id` and `runtime/opencode-secret-id` to
`~/.config/opencode-openbao/role-id` and `secret-id` on the workstation, and
configure the `@xtruder/opencode-openbao` plugin with
`address = "https://bao.${DOMAIN_NAME}"` and
`authorizerUrl = "https://baoauthz.${DOMAIN_NAME}"`.

## Recovery

- `openbao-data` contains encrypted OpenBao storage.
- `openbao-app-data` contains the encrypted SQLite database.
- `runtime/init.json` contains the privileged recovery share and initial root
  token.
- Podman secret `openbao_static_seal_key` is required to decrypt `openbao-data`.
- Podman secret `authorizer_encryption_key` is required to decrypt
  `openbao-app-data`.
- Podman secret `github_app_private_key` is required to reseed GitHub App config.

Losing `openbao_static_seal_key` while keeping `openbao-data` makes that OpenBao
data unrecoverable. The recovery share does not replace the static seal key.
