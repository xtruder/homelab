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
- `dev_password`: generated password for the `dev` user, which mints projects'
  Named Tokens.
- `github_app_private_key`: pasted GitHub App PEM private key.
- `vapid_public_key` and `vapid_private_key`: generated P-256 Web Push keys.
- `openbao_authorizer_token`: initial placeholder replaced during `make setup`.

The first `make setup` replaces the `openbao_authorizer_token` placeholder with
a token OpenBao issues, and writes `runtime/agent-token` for host-side
`bao-cred`. Later runs only reconcile configuration and leave both tokens
alone, so `make setup` is safe to rerun. `make credentials` reconciles and
also reissues both; follow it with `make start`. The old tokens aren't revoked.
The authorizer token is periodic (720h period), and the authorizer renews it
when it starts and every 72 hours, so it doesn't expire while the authorizer
runs. If the authorizer is down for a whole period, run
`make credentials && make start`. `runtime/init.json` contains the initial root token and
single recovery share. Secret backup and recovery policy are operator-owned.

`make setup` reconciles:

- `userpass` users `admin` (full OpenBao administration), `approver` (member
  of `homelab-approvers`, which carries `openbao-authorizer-approver`) and `dev`
  (only `named-identity-minter`, to mint projects' Named Tokens; a 7-day
  token period, renewed whenever bao-cred mints with it). Keep the
  approver's password for the PWA: `bao login` leaves the token in
  `~/.vault-token`, where agents can read it, and an approver token there would
  let them approve their own requests.
- OpenBao CORS for `https://baoauthz.${DOMAIN_NAME}`, because approvers sign in
  to OpenBao directly from the PWA.
- The `named-identity` token role (one Named Token per project, minted with
  `bao-cred init`) and the `agent-session` token role (one child token per agent
  conversation, minted by bao-cred from the Named Token). Both carry the
  `agent-grant-project-<name>` and `agent-grant-global` policies, so project-
  and global-scope Grants reach them.
- The `agent` user on the separate `agents/` userpass mount. Its tokens start
  with no secret access; the authorizer's `host-agent` Requester Rule matches
  every token from that mount, so don't add other users to it.

- The `ssh` secrets engine with an Ed25519 CA, generated once, and the roles
  in `ssh-roles.json`. Setup never writes `ssh/config/ca` again: that would
  rotate the CA every node trusts.

Agents get access only through Grants that an approver approves in the PWA.
Grantable paths are limited to `github/token/project-*` and `ssh/sign/*` (see
`authorizer.hcl`).

Retrieve a generated login password only when needed:

```sh
podman secret inspect --showsecret --format '{{.SecretData}}' admin_password
podman secret inspect --showsecret --format '{{.SecretData}}' approver_password
```

The account-specific installation IDs, account names, repository selectors, and
permission profiles remain tracked in `permission-sets.json`. Sets for one
repository are named `project-<owner>-<repo>`, which `bao-cred git-credential
github/token/project-{owner}-{repo}` picks for git over HTTPS; `make setup`
removes sets no longer listed. `project-xtruder` and `project-offlinehacker`
cover whole organizations, for tools that work across repositories.

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
export BAO_ADDR=https://bao.cloud.x-truder.net BAO_AUTHORIZER_ADDR=https://baoauthz.cloud.x-truder.net
bao login -method=userpass -path=agents username=agent
export BAO_TOKEN="$(bao print token)"
```

Install `bao-cred`, then use:

```sh
BAO_TOKEN="$(cat runtime/agent-token)" bao-cred read --reason "inspect the authorizer repo" \
  --map GH_TOKEN=token github/token/project-xtruder-openbao-authorizer -- \
  gh repo view xtruder/openbao-authorizer
```

On permission denied, `bao-cred` files a Grant Request, waits for approval in
the PWA, retries the read, and exports `GH_TOKEN` only to the child `gh` process.

## Agents in projects

Install the `openbao-grants` skill for your agents
(`npx skills add xtruder/openbao-authorizer --skill openbao-grants -g`), then in
each project, logged in as `dev`:

```sh
export BAO_ADDR=https://bao.${DOMAIN_NAME} BAO_AUTHORIZER_ADDR=https://baoauthz.${DOMAIN_NAME}
bao login -method=userpass username=dev   # podman secret inspect --showsecret --format '{{.SecretData}}' dev_password
bao-cred init        # writes .bao-identity and mints the project's Named Token
```

Agent conversations get their own session tokens automatically; the approver
picks a session, project or global scope for each Grant in the PWA.

## SSH certificates

OpenBao signs short-lived SSH user certificates. Nodes trust the CA's public
key per account, so sshd needs no configuration and nodes never contact
OpenBao.

Each role in `ssh-roles.json` covers one node and user: it signs exactly one
principal, `<user>@<node>`, for 1h with `permit-pty`, port forwarding and agent
forwarding. A role may set
`force_command` to tie it to one command. A Grant covers a path, not the
parameters sent to it, so the role is what limits the certificate: approving
`ssh/sign/jarvis-core` means "may SSH to jarvis as core". The `ssh-cert` rule
allows Grants of up to 8h, during which the Requester may sign any number of
certificates; each stays valid for its own hour, even after the Grant ends.
There is no revocation, so keep certificate TTLs short.

To add a node and user:

1. Add the role to `ssh-roles.json` and run `make setup`.
2. On the node, trust the CA for that account in `~/.ssh/authorized_keys`,
   limited to the role's principal and the tailnet:

   ```text
   cert-authority,principals="core@jarvis",from="100.64.0.0/10,fd7a:115c:a1e0::/48" <ssh/public_key> openbao-ssh-ca
   ```

   chezmoi adds this line on homelab nodes for the `core` user (see
   `dotfiles/dot_ssh/modify_authorized_keys`). The CA public key is public:
   `curl https://bao.${DOMAIN_NAME}/v1/ssh/public_key`.
3. Tailscale SSH must be off on the node; it answers port 22 on the tailnet
   address instead of sshd.

Connect with a throwaway key:

```sh
dir="$(mktemp -d)"; ssh-keygen -q -t ed25519 -N '' -f "$dir/key"
bao-cred write --reason "ssh to jarvis" --field signed_key --output "$dir/key-cert.pub" \
  ssh/sign/jarvis-core public_key=@"$dir/key.pub"
ssh -i "$dir/key" core@jarvis; rm -rf "$dir"
```

## Git commit signing

`signing-keys.json` lists `ed25519` keys in the `transit` engine that sign git
commits through `bao-cred-ssh-keygen`; the private keys never leave OpenBao.
`make setup` creates missing keys and never rotates or deletes one, because
GitHub and every verifier know its public key. The `git-sign` rule lets
Requesters ask for `update` on `transit/sign/git-*`; each Grant (up to 8h)
lets them sign as that key's owner.

Get a key's public half as an SSH key, for GitHub (Settings, SSH and GPG keys,
New SSH key, type **Signing key**) and for `user.signingkey`:

```sh
bao read -field=keys transit/keys/git-offlinehq   # keys.1.public_key: base64 of the raw ed25519 key
```

The bao-cred README ("Signing git commits") has the git configuration.

## Recovery

- `openbao-data` contains encrypted OpenBao storage.
- `openbao-app-data` contains the encrypted SQLite database.
- `runtime/init.json` contains the privileged recovery share and initial root
  token.
- Podman secret `openbao_static_seal_key` is required to decrypt `openbao-data`.
- Podman secret `authorizer_encryption_key` is required to decrypt
  `openbao-app-data`.
- Podman secret `github_app_private_key` is required to reseed GitHub App config.
- The transit signing keys live only in `openbao-data`; losing them means new
  keys and new signing keys on GitHub. Old commits stay verifiable only as long
  as GitHub keeps the old public key.
- The SSH CA's private key lives only in `openbao-data`. Losing it means
  generating a new CA and updating every node's trusted public key.

Losing `openbao_static_seal_key` while keeping `openbao-data` makes that OpenBao
data unrecoverable. The recovery share does not replace the static seal key.
