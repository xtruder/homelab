# OpenBao Authorizer

Homelab deployment for OpenBao Authorizer, its pinned OpenBao server, and
`openbao-plugin-secrets-github`.

## Components

- `openbao`: a thin image based on OpenBao `v2.7.0-beta20260909` that
  contains only the SHA-256-verified GitHub secrets plugin `v0.1.2`; deployment
  configuration is copied separately into a named volume.
- `authorizer`: `ghcr.io/xtruder/openbao-authorizer`, exposed through the shared
  Traefik `proxy` network at `https://openbao-authorizer.x-truder.dev`.

The OpenBao container keeps its upstream/native entrypoint and starts sealed.
Initialization, unsealing, plugin registration, and policy reconciliation happen
**only** through explicit operator scripts. These scripts load `.env` (or `ENV`),
run disposable Bao CLI containers joined to the server container's network
namespace, and never execute Bao inside the server container. `make initialize`
initializes once and writes the root token/unseal key to ignored
`runtime/init.json` with mode `0600`; `make setup` performs the separate
write-only reconciliation. Container restarts apply neither operation.

## Local secrets

Tracked files contain no passwords, tokens, or private keys. Copy `.env.example`
to `.env`, populate it, and place the GitHub App PKCS#1 key at:

```text
secrets/github-app-private-key.pem
```

Both `.env`, `secrets/`, and `runtime/` are ignored. `runtime/` itself is
mode `0700`; the scanner-token file is `0644` only so a non-root container can
read the bind-mounted Compose secret, and remains inaccessible through its host
parent directory. The account-specific App
ID, installation IDs, account names, repository selectors, and permission
profiles are intentionally tracked here in `permission-sets.json`.

## Deploy

The package is private by default. Authenticate Docker to GHCR once using a
GitHub token with `read:packages`:

```sh
gh auth token | docker login ghcr.io -u offlinehacker --password-stdin
```

Then deploy and explicitly configure it:

```sh
make validate
make prepare  # creates the external data volume; no chown/configuration
make deploy   # builds the plugin image and starts OpenBao sealed
make initialize # explicit init/unseal operation
make setup    # explicit plugin/policy/user/GitHub reconciliation
make start    # starts the authorizer after OpenBao is healthy
make status
```

After an OpenBao container or host restart, run `make setup && make start`
again. `make setup` is the only operation that changes OpenBao configuration.

For local image testing, set this in `.env`:

```dotenv
AUTHORIZER_IMAGE=openbao-authorizer:test
```

## Approval-gated GitHub CLI

The stack writes the machine token to ignored `runtime/agent-token`. Use:

```sh
./openbao-gh authorizer -- gh repo view xtruder/openbao-authorizer
./openbao-gh xtruder -- gh repo list xtruder --limit 200
./openbao-gh offlinehacker -- gh repo list offlinehacker --limit 200
```

The helper requests a response-wrapped GitHub installation token, waits for
approval in the PWA, unwraps once, and exports `GH_TOKEN` only to the child
`gh` process.

## Recovery

- `openbao-data` contains encrypted OpenBao storage.
- `authorizer-data` contains the encrypted SQLite database.
- `runtime/init.json` contains the unseal key and root token required to reopen
  `openbao-data` after restart.
- `secrets/github-app-private-key.pem` is required to reseed GitHub App config.

Losing `runtime/init.json` while keeping `openbao-data` makes that OpenBao data
unrecoverable. Do not commit or casually delete it.
