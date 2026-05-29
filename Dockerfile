#
# STAGE1: build linux doc
#
FROM python:3-slim AS builder

RUN apt-get update && apt-get install -y git

WORKDIR /build

RUN git clone --depth 1 https://github.com/torvalds/linux.git .

# Install minimal build dependencies for kernel docs
RUN apt-get install -y \
    make \
    gcc \
    sphinx-common \
    python3-sphinx \
    python3-sphinx-rtd-theme \
    python3-yaml \
    graphviz

RUN CORES=$(( $(nproc) / 2 )); \
    [ $CORES -eq 0 ] && CORES=1; \
    make SPHINXOPTS="-j $CORES" DOCS_THEME=sphinx_rtd_theme htmldocs

#
# STAGE2: build sonaive
#
FROM alpine:latest

ARG ROOT_DIR="/opt/sonaive"

RUN apk add --no-cache s6-overlay python3 py3-jinja2 libqrencode-tools ca-certificates

RUN apk add --no-cache --virtual .build-deps curl jq tar xz

#
#  GID/UID, initial directory
#
RUN addgroup -g 1000 -S docker && \
    adduser -u 1000 -G docker -S docker && \
    mkdir -p ${ROOT_DIR} && \
    chown docker:docker -R ${ROOT_DIR}

#
# www root
#
COPY --chown=docker:docker --from=builder /build/Documentation/output/ ${ROOT_DIR}/www/

#
# Caddy and singbox
#
RUN <<EOF
set -eu

DOWNLOAD_URL=$(curl -fsSL https://api.github.com/repos/klzgrad/forwardproxy/releases/latest \
  | jq -r '.assets[] | select(.name | endswith("caddy-forwardproxy-naive.tar.xz")) | .browser_download_url')
mkdir -p ${ROOT_DIR}/caddy
curl -fsSL "${DOWNLOAD_URL}" | tar -xJf - -C ${ROOT_DIR}/caddy/ --strip-components=1
chmod +x ${ROOT_DIR}/caddy/caddy

DOWNLOAD_URL=$(curl -fsSL https://api.github.com/repos/SagerNet/sing-box/releases/latest \
  | jq -r '.assets[] | select(.name | endswith("-linux-amd64-musl.tar.gz")) | .browser_download_url')
mkdir -p ${ROOT_DIR}/singbox
curl -fsSL "${DOWNLOAD_URL}" | tar -xzf - -C ${ROOT_DIR}/singbox/ --strip-components=1
chmod +x ${ROOT_DIR}/singbox/sing-box

chown -R docker:docker ${ROOT_DIR}/singbox ${ROOT_DIR}/caddy

EOF

#
# Domain files
#
RUN <<EOF
set -eu

DOMAIN_DIR=${ROOT_DIR}/domains

mkdir -p ${DOMAIN_DIR}

curl -fsSL \
  -o "$DOMAIN_DIR/geoip-cn.srs" \
  "https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set/geoip-cn.srs"

curl -fsSL \
  -o "$DOMAIN_DIR/geosite-cn.srs" \
  "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-cn.srs"

curl -fsSL \
  -o "$DOMAIN_DIR/geosite-category-ads-all.srs" \
  "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-category-ads-all.srs"


curl -fsSL \
  -o "$DOMAIN_DIR/hagezi-pro.txt" \
  "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/pro.txt"

curl -fsSL \
  -o "$DOMAIN_DIR/hagezi-tif.txt" \
  "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/tif.txt"

curl -fsSL \
  -o "$DOMAIN_DIR/hagezi-tlds.txt" \
  "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/spam-tlds-adblock.txt"

SINGBOX=${ROOT_DIR}/singbox/sing-box

$SINGBOX rule-set convert \
  --type adguard \
  --output "$DOMAIN_DIR/hagezi-pro.srs" \
  "$DOMAIN_DIR/hagezi-pro.txt"

$SINGBOX rule-set convert \
  --type adguard \
  --output "$DOMAIN_DIR/hagezi-tif.srs" \
  "$DOMAIN_DIR/hagezi-tif.txt"

$SINGBOX rule-set convert \
  --type adguard \
  --output "$DOMAIN_DIR/hagezi-tlds.srs" \
  "$DOMAIN_DIR/hagezi-tlds.txt"

rm "$DOMAIN_DIR/hagezi-tif.txt"
rm "$DOMAIN_DIR/hagezi-tlds.txt"
rm "$DOMAIN_DIR/hagezi-pro.txt"

chown -R docker:docker ${DOMAIN_DIR}

EOF

#
# Configs
#
COPY --chown=docker:docker ./opt ${ROOT_DIR}/

#
# Copy s6 service files
#
COPY --chown=root:root ./s6 /etc/s6-overlay/s6-rc.d/
RUN <<EOF
set -e

chmod +x /etc/s6-overlay/s6-rc.d/singbox/run
chmod +x /etc/s6-overlay/s6-rc.d/caddy/run
chmod +x /etc/s6-overlay/s6-rc.d/init/up
EOF

RUN apk del .build-deps

# 443 is needed for obtaining certificates
EXPOSE 443
VOLUME ${ROOT_DIR}/data
ENTRYPOINT ["/init"]