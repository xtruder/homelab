#!/bin/sh
set -eu
umask 077

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

container_cli="${CONTAINER_CLI:-podman}"
openbao_container="${OPENBAO_CONTAINER:-openbao}"
client_image="${BAO_CLIENT_IMAGE:-quay.io/openbao/openbao:2.7.0-beta20260909}"
plugin_image="${OPENBAO_PLUGIN_IMAGE:-local/openbao:2.7.0-beta20260909}"
runtime="$(pwd)/runtime"
init_file="${runtime}/init.json"
permission_sets="$(pwd)/permission-sets.json"
policies="$(pwd)/policies"
[ -r "${init_file}" ] || { echo 'run initialize-openbao.sh first' >&2; exit 1; }
for secret in github_app_private_key admin_password approver_password agent_password; do
  "${container_cli}" secret inspect "${secret}" >/dev/null 2>&1 || {
    echo "Podman secret is missing: ${secret}; run ./configure-secrets.sh" >&2
    exit 1
  }
done
root_token="$(jq -er '.root_token' "${init_file}")"

bao() {
  "${container_cli}" run --rm \
    --user 0 \
    --security-opt label=disable \
    --network "container:${openbao_container}" \
    -e BAO_ADDR=http://127.0.0.1:8200 \
    -e BAO_TOKEN="${root_token}" \
    -v "${policies}:/policies:ro" \
    --secret github_app_private_key,target=github-app-private-key.pem,mode=0400 \
    --secret admin_password,mode=0400 \
    --secret approver_password,mode=0400 \
    --secret agent_password,mode=0400 \
    --entrypoint bao \
    "${client_image}" "$@"
}

if ! bao auth list -format=json | jq -e 'has("userpass/")' >/dev/null; then
  bao auth enable userpass >/dev/null
fi
bao policy write openbao-authorizer-admin /policies/admin.hcl >/dev/null
bao policy write openbao-authorizer-scanner /policies/scanner.hcl >/dev/null
bao policy write openbao-authorizer-approver /policies/approver.hcl >/dev/null
bao policy write openbao-authorizer-github-agent /policies/github-agent.hcl >/dev/null

plugin_sha="$(${container_cli} run --rm --entrypoint sha256sum "${plugin_image}" /openbao/plugins/openbao-plugin-secrets-github | cut -d' ' -f1)"
bao plugin register -sha256="${plugin_sha}" -command=openbao-plugin-secrets-github secret openbao-plugin-secrets-github >/dev/null
if ! bao secrets list -format=json | jq -e 'has("github/")' >/dev/null; then
  bao secrets enable -path=github -plugin-name=openbao-plugin-secrets-github plugin >/dev/null
fi

bao write auth/userpass/users/admin password=@/run/secrets/admin_password policies=openbao-authorizer-admin token_period=24h >/dev/null
bao write auth/userpass/users/approver password=@/run/secrets/approver_password policies=openbao-authorizer-approver token_period=24h >/dev/null
bao write auth/userpass/users/agent password=@/run/secrets/agent_password policies=openbao-authorizer-github-agent >/dev/null
approver_login="$(bao write -format=json auth/userpass/login/approver password=@/run/secrets/approver_password)"
agent_login="$(bao write -format=json auth/userpass/login/agent password=@/run/secrets/agent_password)"
approver_entity="$(printf '%s' "${approver_login}" | jq -er '.auth.entity_id')"
agent_entity="$(printf '%s' "${agent_login}" | jq -er '.auth.entity_id')"
bao write identity/group name=homelab-approvers type=internal member_entity_ids="${approver_entity}" policies=openbao-authorizer-approver >/dev/null
bao write identity/group name=homelab-agents type=internal member_entity_ids="${agent_entity}" policies=openbao-authorizer-github-agent >/dev/null

bao write github/config app_id="${GITHUB_APP_ID}" prv_key=@/secrets/github-app-private-key.pem exclude_repository_metadata=true >/dev/null
jq -c '.permission_sets | to_entries[]' "${permission_sets}" | while IFS= read -r entry; do
  name="$(printf '%s' "${entry}" | jq -er '.key')"
  profile="$(printf '%s' "${entry}" | jq -er '.value.permissions_profile')"
  payload_file="${runtime}/permission-set-${name}.json"
  printf '%s' "${entry}" | jq --arg profile "${profile}" --slurpfile config "${permission_sets}" \
    '.value | del(.permissions_profile) + {permissions: $config[0].permission_profiles[$profile]}' >"${payload_file}"
  "${container_cli}" run --rm \
    --user 0 \
    --security-opt label=disable \
    --network "container:${openbao_container}" \
    -e BAO_ADDR=http://127.0.0.1:8200 \
    -e BAO_TOKEN="${root_token}" \
    -v "${payload_file}:/permission-set.json:ro" \
    --entrypoint bao \
    "${client_image}" write "github/permissionset/${name}" @/permission-set.json >/dev/null
  rm -f "${payload_file}"
done

scanner="$(bao write -format=json auth/token/create-orphan policies=openbao-authorizer-scanner no_default_policy=true ttl=720h renewable=false | jq -er '.auth.client_token')"
printf '%s' "${scanner}" | "${container_cli}" secret create --replace openbao_scanner_token - >/dev/null
unset scanner
printf '%s\n' "${agent_login}" | jq -er '.auth.client_token' >"${runtime}/agent-token"
chmod 0600 "${runtime}/agent-token"

echo 'OpenBao configuration reconciled.'
