# OpenBao Authorizer

Homelab deployment for OpenBao Authorizer, its pinned OpenBao server, and
`openbao-plugin-secrets-github`.

## Components

- `openbao`: a thin image based on OpenBao `v2.7.0-beta20260909` that
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
- `agent_password`: generated setup-only user password.
- `github_app_private_key`: pasted GitHub App PEM private key.
- `vapid_public_key` and `vapid_private_key`: generated P-256 Web Push keys.
- `openbao_scanner_token`: initial placeholder replaced during `make setup`.

`make setup` creates or replaces the generated `openbao_scanner_token` Podman
secret after OpenBao issues the token. It writes only `runtime/agent-token` for
host-side `bao-cred` use. `runtime/init.json` contains the initial root token and
single recovery share. Secret backup and recovery policy are operator-owned.

`make setup` enables `userpass` and reconciles three users:

- `admin`: full OpenBao administration through `openbao-authorizer-admin`.
- `approver`: control-group approval through `openbao-authorizer-approver`.
- `agent`: requests approval-gated GitHub tokens; setup exchanges its login for
  `runtime/agent-token`.

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

For local image testing, set this in `.env`:

```dotenv
AUTHORIZER_IMAGE=openbao-authorizer:test
```

## Approval-gated GitHub CLI

The stack writes the machine token to ignored `runtime/agent-token`. Install
`bao-cred`, then use:

```sh
BAO_ADDR=https://bao.x-truder.net bao-cred -token-file runtime/agent-token \
  -map GH_TOKEN=token github/token/project-authorizer -- \
  gh repo view xtruder/openbao-authorizer

BAO_ADDR=https://bao.x-truder.net bao-cred -token-file runtime/agent-token \
  -map GH_TOKEN=token github/token/project-xtruder -- \
  gh repo list xtruder --limit 200

BAO_ADDR=https://bao.x-truder.net bao-cred -token-file runtime/agent-token \
  -map GH_TOKEN=token github/token/project-offlinehacker -- \
  gh repo list offlinehacker --limit 200
```

`bao-cred` requests a response-wrapped GitHub installation token, waits for
approval in the PWA, unwraps once, and exports `GH_TOKEN` only to the child `gh`
process.

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
