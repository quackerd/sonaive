#!/bin/sh
set -eu

ROOT_DIR=/opt/sonaive
DATA_DIR="${ROOT_DIR}/data"

# The bind mount arrives owned by root; hand it to the runtime user before
# Caddy writes its config, certificate and home directories into it.
mkdir -p "${DATA_DIR}"
chown -R docker:docker "${DATA_DIR}"

su-exec docker python3 "${ROOT_DIR}/init.py"

exec su-exec docker env \
    XDG_CONFIG_HOME="${DATA_DIR}/caddy/config" \
    XDG_DATA_HOME="${DATA_DIR}/caddy/data" \
    HOME="${DATA_DIR}/caddy/home" \
    "${ROOT_DIR}/caddy/caddy" run --config "${ROOT_DIR}/caddyfile" --adapter caddyfile
