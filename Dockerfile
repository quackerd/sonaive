FROM alpine:latest

ARG ROOT_DIR="/opt/sonaive"

RUN apk add --no-cache python3 py3-jinja2 libqrencode-tools ca-certificates su-exec

#
#  GID/UID, initial directory
#
RUN addgroup -g 1000 -S docker && \
    adduser -u 1000 -G docker -S docker && \
    mkdir -p "${ROOT_DIR}" && \
    chown docker:docker -R "${ROOT_DIR}"

#
# Caddy
#
RUN <<EOF
set -euxo pipefail

apk add --no-cache --virtual .build-deps curl jq tar xz

DOWNLOAD_URL=$(curl -fsSL https://api.github.com/repos/klzgrad/forwardproxy/releases/latest \
  | jq -r '.assets[] | select(.name | endswith("caddy-forwardproxy-naive.tar.xz")) | .browser_download_url')
mkdir -p "${ROOT_DIR}/caddy"
curl -fsSL "${DOWNLOAD_URL}" | tar -xJf - -C "${ROOT_DIR}/caddy/" --strip-components=1
chmod +x "${ROOT_DIR}/caddy/caddy"
echo "Caddy+Naive: $DOWNLOAD_URL"

chown -R docker:docker "${ROOT_DIR}/caddy"

apk del .build-deps
EOF

#
# Configs
#
COPY --chown=docker:docker ./opt "${ROOT_DIR}/"

RUN chmod +x "${ROOT_DIR}/entrypoint.sh"

# 80 is needed for ACME HTTP-01 challenges, 443 for the proxy itself
EXPOSE 80 443
VOLUME ${ROOT_DIR}/data
ENTRYPOINT ["/opt/sonaive/entrypoint.sh"]
