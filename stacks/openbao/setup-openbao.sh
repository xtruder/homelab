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
[ -r "${init_file}" ] || { echo 'run initialize-openbao.sh first' >&2; exit 1; }
for secret in github_app_private_key admin_password approver_password; do
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
if ! bao auth list -format=json | jq -e 'has("approle/")' >/dev/null; then
  bao auth enable approle >/dev/null
fi
# A separate AppRole mount for host agents: the authorizer's "host-agent"
# Requester Rule matches every token from this mount, so the opencode minter
# on approle/ must not share it.
if ! bao auth list -format=json | jq -e 'has("agents/")' >/dev/null; then
  bao auth enable -path=agents approle >/dev/null
fi
bao policy write openbao-authorizer-admin /policies/admin.hcl >/dev/null
bao policy write openbao-authorizer /policies/authorizer.hcl >/dev/null
bao policy write openbao-authorizer-approver /policies/approver.hcl >/dev/null
bao policy write opencode-minter /policies/opencode-minter.hcl >/dev/null
bao policy write opencode-session /policies/opencode-session.hcl >/dev/null

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
approver_login="$(bao write -format=json auth/userpass/login/approver password=@/run/secrets/approver_password)"
approver_entity="$(printf '%s' "${approver_login}" | jq -er '.auth.entity_id')"
bao token revoke "$(printf '%s' "${approver_login}" | jq -er '.auth.client_token')" >/dev/null
bao write identity/group name=homelab-approvers type=internal member_entity_ids="${approver_entity}" policies=openbao-authorizer-approver >/dev/null
# Session Tokens: one entity alias, and so one identity, per opencode session.
bao write auth/token/roles/opencode-session allowed_policies=opencode-session orphan=true renewable=true \
  token_period=24h allowed_entity_aliases='opencode-session-*' >/dev/null
# The opencode plugin logs in with this AppRole only to mint Session Tokens.
bao write auth/approle/role/opencode-minter token_policies=opencode-minter token_ttl=15m token_max_ttl=1h >/dev/null
# Host agents start with no secret access; everything arrives as Grants.
bao write auth/agents/role/host-agent token_policies=default token_ttl=720h token_max_ttl=720h >/dev/null

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

begin_step 'issue authorizer, host agent and opencode minter credentials'
# The authorizer doesn't renew its token; rerun make setup and make start
# within 30 days.
authorizer="$(bao write -format=json auth/token/create-orphan policies=openbao-authorizer no_default_policy=true ttl=720h renewable=false | jq -er '.auth.client_token')"
printf '%s' "${authorizer}" | "${container_cli}" secret create --replace openbao_authorizer_token - >/dev/null
unset authorizer
agent_role_id="$(bao read -field=role_id auth/agents/role/host-agent/role-id)"
agent_secret_id="$(bao write -f -field=secret_id auth/agents/role/host-agent/secret-id)"
bao write -field=token auth/agents/login role_id="${agent_role_id}" secret_id="${agent_secret_id}" >"${runtime}/agent-token"
unset agent_role_id agent_secret_id
# Copy these to ~/.config/opencode-openbao/ on the workstation running opencode.
bao read -field=role_id auth/approle/role/opencode-minter/role-id >"${runtime}/opencode-role-id"
bao write -f -field=secret_id auth/approle/role/opencode-minter/secret-id >"${runtime}/opencode-secret-id"
chmod 0600 "${runtime}/agent-token" "${runtime}/opencode-role-id" "${runtime}/opencode-secret-id"

setup_step="complete"
echo 'OpenBao configuration reconciled.'
