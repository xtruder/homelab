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

container_cli="${CONTAINER_CLI:-docker}"
openbao_container="${OPENBAO_CONTAINER:-openbao-authorizer-openbao}"
client_image="${BAO_CLIENT_IMAGE:-quay.io/openbao/openbao:2.7.0-beta20260909}"
runtime="$(pwd)/runtime"
init_file="${runtime}/init.json"
mkdir -p "${runtime}"
chmod 0700 "${runtime}"

bao() {
  "${container_cli}" run --rm \
    --network "container:${openbao_container}" \
    -e BAO_ADDR=http://127.0.0.1:8200 \
    --entrypoint bao \
    "${client_image}" "$@"
}

status="$(bao status -format=json 2>/dev/null || true)"
[ -n "${status}" ] || { echo 'OpenBao is not reachable' >&2; exit 1; }

if [ "$(printf '%s' "${status}" | jq -r '.initialized')" != true ]; then
  bao operator init -format=json -key-shares=1 -key-threshold=1 >"${init_file}"
  chmod 0600 "${init_file}"
elif [ ! -r "${init_file}" ]; then
  echo 'OpenBao is initialized but runtime/init.json is missing; cannot unseal' >&2
  exit 1
fi

status="$(bao status -format=json 2>/dev/null || true)"
if [ "$(printf '%s' "${status}" | jq -r '.sealed')" = true ]; then
  bao operator unseal "$(jq -er '.unseal_keys_b64[0]' "${init_file}")" >/dev/null
fi

echo 'OpenBao initialized and unsealed; no policies or application configuration were written.'
