#!/bin/sh
set -e

: "${DERP_HOSTNAME:?DERP_HOSTNAME must be set}"

DATA_DIR=/var/lib/derper
CERT_DIR=${DATA_DIR}/certs
CRT=${CERT_DIR}/${DERP_HOSTNAME}.crt
KEY=${CERT_DIR}/${DERP_HOSTNAME}.key

# Self-signed instead of a public CA cert: publicly issued certs end up in CT
# logs, which get scraped and blocked (e.g. by the GFW). Clients pin the cert
# by hash via CertName in the DERP map, so it never has to chain to a CA.
if [ ! -f "$CRT" ] || [ ! -f "$KEY" ]; then
    mkdir -p "$CERT_DIR"
    openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes \
        -days 3650 -subj "/CN=${DERP_HOSTNAME}" \
        -addext "subjectAltName=DNS:${DERP_HOSTNAME}" \
        -keyout "$KEY" -out "$CRT"
fi

echo "DERP map CertName: sha256-raw:$(openssl x509 -in "$CRT" -outform der | sha256sum | cut -d' ' -f1)"

# TLS is terminated here, traefik only does SNI passthrough. STUN is disabled
# as only 443/tcp is exposed.
exec derper \
    -a :443 \
    -http-port -1 \
    -stun=false \
    -certmode manual \
    -certdir "$CERT_DIR" \
    -hostname "$DERP_HOSTNAME" \
    -c "$DATA_DIR/derper.key" \
    -home blank \
    -verify-clients \
    "$@"
