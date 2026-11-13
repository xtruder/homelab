#!/bin/sh
set -eu
umask 077

setup_step="preflight"
report_failure() {
  status=$?
  [ "${status}" -eq 0 ] || echo "OpenBao setup failed during: ${setup_step}" >&2
}
trap report_failure EXIT

begin_step() {
  setup_step="$1"
  echo "==> ${setup_step}"
}

env_file="${ENV:-.env}"
case "${env_file}" in
  /*) ;;
  *) env_file="$(pwd)/${env_file}" ;;
esac
[ -r "${env_file}" ] || { echo "environment file is not readable: ${env_file}" >&2; exit 1; }
set -a
# shellcheck source=/dev/null
. "${env_file}"
set +a

container_cli="podman"
compose="${COMPOSE:-podman-compose}"
runtime="$(pwd)/runtime"
init_file="${runtime}/init.json"
permission_sets="$(pwd)/permission-sets.json"
ssh_roles="$(pwd)/ssh-roles.json"
signing_keys="$(pwd)/signing-keys.json"
[ -r "${init_file}" ] || { echo 'run initialize-openbao.sh first' >&2; exit 1; }
for secret in github_app_private_key admin_password approver_password agent_password dev_password; do
  "${container_cli}" secret inspect "${secret}" >/dev/null 2>&1 || {
    echo "Podman secret is missing: ${secret}; run ./configure-secrets.sh" >&2
    exit 1
  }
done
root_token="$(jq -er '.root_token' "${init_file}")"

bao() {
  "${compose}" --env-file "${env_file}" --profile tools run --rm -T \
    -e BAO_TOKEN="${root_token}" bao "$@"
}

begin_step 'configure auth methods and policies'
if ! bao auth list -format=json | jq -e 'has("userpass/")' >/dev/null; then
  bao auth enable userpass >/dev/null
fi
# A separate userpass mount for host agents: the authorizer's "host-agent"
# Requester Rule matches every token from this mount, so admin and approver on
# userpass/ must not share it.
if ! bao auth list -format=json | jq -e 'has("agents/")' >/dev/null; then
  bao auth enable -path=agents userpass >/dev/null
fi
bao policy write openbao-authorizer-admin /policies/admin.hcl >/dev/null
bao policy write openbao-authorizer /policies/authorizer.hcl >/dev/null
bao policy write openbao-authorizer-approver /policies/approver.hcl >/dev/null
bao policy write named-identity /policies/named-identity.hcl >/dev/null
bao policy write named-identity-minter /policies/named-identity-minter.hcl >/dev/null
bao policy write agent-session /policies/agent-session.hcl >/dev/null

begin_step 'allow the authorizer origin to sign approvers in to OpenBao'
bao write sys/config/cors enabled=true allowed_origins="https://baoauthz.${DOMAIN_NAME}" \
  allowed_headers=X-Vault-Token,X-Vault-Namespace,X-Vault-Request,Content-Type >/dev/null

begin_step 'register and enable the GitHub secrets plugin'
plugin_sha="$("${compose}" --env-file "${env_file}" exec -T openbao sha256sum /openbao/plugins/openbao-plugin-secrets-github | cut -d' ' -f1)"
bao plugin register -sha256="${plugin_sha}" -command=openbao-plugin-secrets-github secret openbao-plugin-secrets-github >/dev/null
if ! bao secrets list -format=json | jq -e 'has("github/")' >/dev/null; then
  bao secrets enable -path=github -plugin-name=openbao-plugin-secrets-github plugin >/dev/null
fi

begin_step 'reconcile users, roles and identity groups'
bao write auth/userpass/users/admin password=@/run/secrets/admin_password policies=openbao-authorizer-admin token_period=24h >/dev/null
bao write auth/userpass/users/approver password=@/run/secrets/approver_password policies=openbao-authorizer-approver token_period=24h >/dev/null
# dev only mints projects' Named Tokens with bao-cred init. It is separate from
# the approver because `bao login` leaves its token in ~/.vault-token, where
# agents can read it, and an approver token would let them approve their own
# requests. Its token's 7-day period lets ~/.vault-token live on while bao-cred
# keeps minting with it, which renews it.
bao write auth/userpass/users/dev password=@/run/secrets/dev_password policies=named-identity-minter token_period=168h >/dev/null
approver_login="$(bao write -format=json auth/userpass/login/approver password=@/run/secrets/approver_password)"
approver_entity="$(printf '%s' "${approver_login}" | jq -er '.auth.entity_id')"
bao token revoke "$(printf '%s' "${approver_login}" | jq -er '.auth.client_token')" >/dev/null
bao write identity/group name=homelab-approvers type=internal member_entity_ids="${approver_entity}" policies=openbao-authorizer-approver >/dev/null
# Named Tokens: one per project, alias <name>. Agent session tokens: minted by
# a Named Token as its children, alias <name>.<session id>. Both carry the
# project and global Grant policies, which the authorizer writes.
bao write auth/token/roles/named-identity allowed_policies=named-identity,agent-grant-global \
  allowed_policies_glob='agent-grant-project-*' orphan=true renewable=true token_period=768h allowed_entity_aliases='*' >/dev/null
bao write auth/token/roles/agent-session allowed_policies=agent-session,agent-grant-global \
  allowed_policies_glob='agent-grant-project-*' orphan=false renewable=true token_period=24h allowed_entity_aliases='*' >/dev/null
# Host agents start with no secret access; everything arrives as Grants.
bao write auth/agents/users/agent password=@/run/secrets/agent_password token_policies=default token_ttl=720h token_max_ttl=720h >/dev/null

begin_step 'configure the GitHub App'
bao write github/config app_id="${GITHUB_APP_ID}" prv_key=@/run/secrets/github-app-private-key.pem exclude_repository_metadata=true >/dev/null
begin_step 'reconcile GitHub permission sets'
jq -c '.permission_sets | to_entries[]' "${permission_sets}" | while IFS= read -r entry; do
  name="$(printf '%s' "${entry}" | jq -er '.key')"
  echo "  - ${name}"
  profile="$(printf '%s' "${entry}" | jq -er '.value.permissions_profile')"
  payload_file="${runtime}/permission-set-${name}.json"
  printf '%s' "${entry}" | jq --arg profile "${profile}" --slurpfile config "${permission_sets}" \
    '.value | del(.permissions_profile) + {permissions: $config[0].permission_profiles[$profile]}' >"${payload_file}"
  "${compose}" --env-file "${env_file}" --profile tools run --rm -T \
    -e BAO_TOKEN="${root_token}" \
    -v "${payload_file}:/permission-set.json:ro" \
    bao write "github/permissionset/${name}" @/permission-set.json </dev/null >/dev/null
  rm -f "${payload_file}"
done

begin_step 'configure the SSH certificate authority'
if ! bao secrets list -format=json | jq -e 'has("ssh/")' >/dev/null; then
  bao secrets enable ssh >/dev/null
fi
# Writing ssh/config/ca again would replace the default issuer, rotating the
# CA that every node trusts. Generate it only when there is no issuer: bao
# list exits 2 when the list is empty, and any other failure stops setup.
set +e
bao list ssh/issuers >/dev/null
issuers_status=$?
set -e
case "${issuers_status}" in
  0) ;;
  2) bao write ssh/config/ca generate_signing_key=true key_type=ssh-ed25519 >/dev/null ;;
  *) echo "listing SSH issuers failed with status ${issuers_status}" >&2; exit 1 ;;
esac

begin_step 'reconcile SSH roles'
# Grants cover paths, not parameters, so each role fixes everything a
# certificate may carry: one principal, the TTL and the extensions. Requested
# critical options replace the role's defaults, including a force-command, so
# the only one allowed is a name sshd doesn't know, which makes it refuse the
# certificate.
jq -c '.defaults as $defaults | .roles | to_entries[] | {name: .key, role: ($defaults + .value)}' "${ssh_roles}" | while IFS= read -r entry; do
  name="$(printf '%s' "${entry}" | jq -er '.name')"
  echo "  - ${name}"
  payload_file="${runtime}/ssh-role-${name}.json"
  printf '%s' "${entry}" | jq '.role | {
    key_type: "ca",
    allow_user_certificates: true,
    allow_host_certificates: false,
    allowed_users: .principal,
    default_user: .principal,
    allow_user_key_ids: false,
    key_id_format: "{{role_name}}-{{token_display_name}}-{{public_key_hash}}",
    ttl: .ttl,
    max_ttl: .ttl,
    allowed_extensions: (.extensions | join(",")),
    default_extensions: (.extensions | map({key: ., value: ""}) | from_entries),
    allowed_critical_options: "deny-overrides@x-truder.net",
    default_critical_options: (if .force_command then {"force-command": .force_command} else {} end)
  }' >"${payload_file}"
  "${compose}" --env-file "${env_file}" --profile tools run --rm -T \
    -e BAO_TOKEN="${root_token}" \
    -v "${payload_file}:/ssh-role.json:ro" \
    bao write "ssh/roles/${name}" @/ssh-role.json </dev/null >/dev/null
  rm -f "${payload_file}"
done
# A role removed from ssh-roles.json must stop being signable.
set +e
existing_roles="$(bao list -format=json ssh/roles)"
roles_status=$?
set -e
case "${roles_status}" in
  0) ;;
  2) existing_roles='[]' ;;
  *) echo "listing SSH roles failed with status ${roles_status}" >&2; exit 1 ;;
esac
printf '%s' "${existing_roles}" | jq -r --slurpfile config "${ssh_roles}" '.[] | . as $name | select($config[0].roles | has($name) | not)' | while IFS= read -r name; do
  echo "  - removing ${name}"
  bao delete "ssh/roles/${name}" </dev/null >/dev/null
done

begin_step 'reconcile git signing keys'
if ! bao secrets list -format=json | jq -e 'has("transit/")' >/dev/null; then
  bao secrets enable transit >/dev/null
fi
# Keys are created once and never rotated or deleted here: GitHub and every
# verifier know the public key, and old commits stay signed by it. ed25519,
# not exportable, so the private key never leaves OpenBao.
jq -r '.keys[]' "${signing_keys}" | while IFS= read -r name; do
  echo "  - ${name}"
  if ! bao read "transit/keys/${name}" </dev/null >/dev/null 2>&1; then
    bao write "transit/keys/${name}" type=ed25519 exportable=false allow_plaintext_backup=false </dev/null >/dev/null
  fi
done

# Reissuing creates new tokens without revoking the old ones and needs an
# authorizer restart, so it happens only on first setup or when asked for
# (make credentials).
authorizer_secret="$("${container_cli}" secret inspect --showsecret --format '{{.SecretData}}' openbao_authorizer_token 2>/dev/null || true)"
if [ "${ISSUE_CREDENTIALS:-0}" = 1 ] || [ -z "${authorizer_secret}" ] || [ "${authorizer_secret}" = pending-initial-setup ]; then
  begin_step 'issue the authorizer token'
  # A periodic token, which the authorizer renews at start and every 72h.
  authorizer="$(bao write -format=json auth/token/create-orphan policies=openbao-authorizer no_default_policy=true period=720h renewable=true | jq -er '.auth.client_token')"
  printf '%s' "${authorizer}" | "${container_cli}" secret create --replace openbao_authorizer_token - >/dev/null
  unset authorizer
  echo '  run make start so the authorizer uses it'
fi
unset authorizer_secret
if [ "${ISSUE_CREDENTIALS:-0}" = 1 ] || [ ! -s "${runtime}/agent-token" ]; then
  begin_step 'issue the host agent token'
  bao write -field=token auth/agents/login/agent password=@/run/secrets/agent_password >"${runtime}/agent-token"
  chmod 0600 "${runtime}/agent-token"
fi

setup_step="complete"
echo 'OpenBao configuration reconciled.'
