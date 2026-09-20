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
  bao operator init -format=json -recovery-shares=1 -recovery-threshold=1 >"${init_file}"
  chmod 0600 "${init_file}"
elif [ ! -r "${init_file}" ]; then
  echo 'OpenBao is initialized but runtime/init.json is missing; cannot unseal' >&2
  exit 1
fi

for _ in $(seq 1 50); do
  status="$(bao status -format=json 2>/dev/null || true)"
  [ "$(printf '%s' "${status}" | jq -r '.sealed // true')" = false ] && break
  sleep 0.2
done
[ "$(printf '%s' "${status}" | jq -r '.sealed // true')" = false ] || {
  echo 'OpenBao remained sealed; verify the static seal key mount' >&2
  exit 1
}

echo 'OpenBao initialized and auto-unsealed; no policies or application configuration were written.'
