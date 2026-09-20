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

## Local secrets

Tracked files contain no passwords, tokens, or private keys. Copy `.env.example`
to `.env`, populate it, and place the GitHub App PKCS#1 key at:

```text
secrets/github-app-private-key.pem
secrets/authorizer-encryption-key
secrets/vapid-public-key
secrets/vapid-private-key
```

Both `.env`, `secrets/`, and `runtime/` are ignored. The tracked `authorizer.hcl`
reads non-secret deployment values through explicit `env.*` expressions. The
authorizer encryption key must contain the base64 encoding of exactly 32 bytes;
generate it with `openssl rand -base64 32`. `runtime/` itself is mode `0700`; the
scanner-token file is `0644` only so a non-root container can read the
bind-mounted Compose secret, and remains inaccessible through its host parent
directory. The account-specific App
ID, installation IDs, account names, repository selectors, and permission
profiles are intentionally tracked here in `permission-sets.json`.

`make deploy` generates `secrets/openbao-static-seal.key` once if it does not
already exist. It never overwrites the key. Back this 32-byte file up off-host
before storing data: the recovery share in `runtime/init.json` does not replace
the static seal key, and losing the seal key makes the Raft data unrecoverable.
The file is mode `0644` so rootless Podman can expose it to OpenBao's non-root
user; the containing ignored `secrets/` directory remains mode `0700`.

## Deploy

Then deploy and explicitly configure it:

```sh
make validate
make deploy   # builds the plugin image and starts OpenBao sealed
make initialize # explicit init/unseal operation
make setup    # explicit plugin/policy/user/GitHub reconciliation
make start    # starts the authorizer after OpenBao is healthy
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
- `secrets/openbao-static-seal.key` is required to decrypt `openbao-data`.
- `secrets/github-app-private-key.pem` is required to reseed GitHub App config.

Losing `secrets/openbao-static-seal.key` while keeping `openbao-data` makes that
OpenBao data unrecoverable. Keep an off-host backup; do not commit either it or
`runtime/init.json`.
