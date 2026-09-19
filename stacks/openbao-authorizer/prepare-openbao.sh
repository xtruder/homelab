#!/bin/sh
set -eu

# Named volumes mount with the ownership declared by their images. This helper
# only ensures the OpenBao data volume exists before Compose references it as
# external; it does not modify permissions or OpenBao configuration.
docker volume create openbao-authorizer-data >/dev/null
mkdir -p runtime
chmod 0700 runtime

echo 'External OpenBao data volume exists; no permissions or configuration were changed.'
