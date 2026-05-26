#
# STAGE1: build linux doc
#
FROM python:3.11-slim AS builder

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

RUN apk add --no-cache s6-overlay python3 py3-jinja2 libqrencode-tools bind-tools

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
# Caddy and MosDNS
#
RUN <<EOF
set -e

apk add --no-cache curl jq unzip

DOWNLOAD_URL=$(curl -s https://api.github.com/repos/klzgrad/forwardproxy/releases/latest \
  | jq -r '.assets[] | select(.name | endswith("caddy-forwardproxy-naive.tar.xz")) | .browser_download_url')
mkdir -p ${ROOT_DIR}/caddy
curl -fSL "${DOWNLOAD_URL}" | tar -xvJ -C ${ROOT_DIR}/caddy/ --strip-components=1

DOWNLOAD_URL=$(curl -s https://api.github.com/repos/IrineSistiana/mosdns/releases \
  | jq -r '[.[] | select((.tag_name | startswith("v5.")) and .prerelease == false)] | first | .assets[] | select(.name | endswith("mosdns-linux-amd64.zip")) | .browser_download_url')
mkdir -p ${ROOT_DIR}/mosdns
curl -fSL -o /tmp/mosdns.zip "${DOWNLOAD_URL}"
unzip -o /tmp/mosdns.zip -d ${ROOT_DIR}/mosdns
rm /tmp/mosdns.zip

chown -R docker:docker ${ROOT_DIR}/mosdns ${ROOT_DIR}/caddy

apk del curl jq unzip
EOF

#
# Domain files
#
RUN <<EOF
set -e

DOMAIN_DIR=${ROOT_DIR}/domains

mkdir -p ${DOMAIN_DIR}

# CN domain list
wget -q -O ${DOMAIN_DIR}/cn-list.txt "https://raw.githubusercontent.com/Loyalsoldier/v2ray-rules-dat/release/china-list.txt"
wget -q -O ${DOMAIN_DIR}/cn-tld.txt "https://raw.githubusercontent.com/Loyalsoldier/v2ray-rules-dat/release/direct-tld-list.txt"

# private IP list
wget -q -O ${DOMAIN_DIR}/private-ip.txt "https://raw.githubusercontent.com/Loyalsoldier/geoip/refs/heads/release/text/private.txt"

# CN IP list
wget -q -O ${DOMAIN_DIR}/cn-ip.txt "https://raw.githubusercontent.com/Loyalsoldier/geoip/refs/heads/release/text/cn.txt"

# HaGeZi Pro Core (High-coverage ad/tracker/telemetry blocking with strict allowlisting)
wget -q -O ${DOMAIN_DIR}/pro.txt "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/domains/pro.txt"

# HaGeZi Threat Intelligence Feed (Silent malicious infrastructure firewall)
wget -q -O ${DOMAIN_DIR}/tif.txt "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/domains/tif.txt"

# HaGeZi Most Abused TLDs - Protects against known malicious Top Level Domains
wget -q -O ${DOMAIN_DIR}/tld.txt "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/wildcard/spam-tlds-onlydomains.txt"

# HaGeZi Most Abused TLDs Allow List
wget -q -O ${DOMAIN_DIR}/tld-allow.txt "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/wildcard/spam-tlds-onlydomains.txt"

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

chmod +x /etc/s6-overlay/s6-rc.d/mosdns/run
chmod +x /etc/s6-overlay/s6-rc.d/caddy/run
chmod +x /etc/s6-overlay/s6-rc.d/init/up
EOF

# args
ENV PORT=443
ENV BLOCK_CN=true
ENV BLOCK_LOCAL=true
ENV BLOCK_ADS=true
ENV DEFAULT_SITE=true
ENV LOG_LEVEL=info
ENV DEV=false

# 443 is needed for obtaining certificates
EXPOSE 443
VOLUME ${ROOT_DIR}/data
ENTRYPOINT ["/init"]