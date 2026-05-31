FROM alpine:latest

ARG ROOT_DIR="/opt/sonaive"

RUN apk add --no-cache s6-overlay python3 py3-jinja2 libqrencode-tools ca-certificates

RUN apk add --no-cache --virtual .build-deps curl jq tar xz

#
#  GID/UID, initial directory
#
RUN addgroup -g 1000 -S docker && \
    adduser -u 1000 -G docker -S docker && \
    mkdir -p "${ROOT_DIR}" && \
    chown docker:docker -R "${ROOT_DIR}"

#
# www root
#
# https://git.quacker.org/d/layer-linux-docs
COPY --chown=docker:docker --from=quackerd/layer-linux-docs:latest "/www/" "${ROOT_DIR}/www/"

#
# Caddy and singbox
#
RUN <<EOF
set -euo pipefail

DOWNLOAD_URL=$(curl -fsSL https://api.github.com/repos/klzgrad/forwardproxy/releases/latest \
  | jq -r '.assets[] | select(.name | endswith("caddy-forwardproxy-naive.tar.xz")) | .browser_download_url')
mkdir -p "${ROOT_DIR}/caddy"
curl -fsSL "${DOWNLOAD_URL}" | tar -xJf - -C "${ROOT_DIR}/caddy/" --strip-components=1
chmod +x "${ROOT_DIR}/caddy/caddy"

DOWNLOAD_URL=$(curl -fsSL https://api.github.com/repos/SagerNet/sing-box/releases/latest \
  | jq -r '.assets[] | select(.name | endswith("-linux-amd64-musl.tar.gz")) | .browser_download_url')
mkdir -p "${ROOT_DIR}/singbox"
curl -fsSL "${DOWNLOAD_URL}" | tar -xzf - -C "${ROOT_DIR}/singbox/" --strip-components=1
chmod +x "${ROOT_DIR}/singbox/sing-box"

chown -R docker:docker "${ROOT_DIR}/singbox" "${ROOT_DIR}/caddy"

EOF

#
# Domain files
#
RUN <<EOF
set -euo pipefail

SINGBOX=${ROOT_DIR}/singbox/sing-box

merge_srs_urls() {
    out=$1
    shift

    [ -n "$out" ] && [ "$#" -gt 0 ] || {
        echo "usage: merge_srs_urls OUTPUT.srs URL..." >&2
        return 1
    }

    tmp_dir=$(mktemp -d) || return 1

    merge_args=""

    i=0
    for url in "$@"; do
        i=$((i + 1))

        curl -fsSL -o "$tmp_dir/$i.srs" "$url"

        "$SINGBOX" rule-set decompile \
            --output "$tmp_dir/$i.json" \
            "$tmp_dir/$i.srs"

        merge_args="$merge_args -c $tmp_dir/$i.json"
    done

    # shellcheck disable=SC2086
    "$SINGBOX" rule-set merge "$tmp_dir/merged.json" $merge_args

    "$SINGBOX" rule-set compile \
        --output "$out" \
        "$tmp_dir/merged.json"

    rm -rf "$tmp_dir"
}

compile_adblock_txt_urls() {
    out=$1
    shift

    [ -n "$out" ] && [ "$#" -gt 0 ] || {
        echo "usage: compile_adblock_txt_urls OUTPUT.srs URL..." >&2
        return 1
    }

    tmp_dir=$(mktemp -d) || return 1

    merged_txt="$tmp_dir/merged.txt"
    source_json="$tmp_dir/source.json"

    : > "$merged_txt"

    for url in "$@"; do
        echo "Downloading: $url" >&2
        curl -fsSL "$url" >> "$merged_txt"
        printf '\n' >> "$merged_txt"
    done

    sort -u "$merged_txt" -o "$merged_txt"

    "$SINGBOX" rule-set convert \
        --type adguard \
        --output "$out" \
        "$merged_txt"

    rm -rf "$tmp_dir"
}


DOMAIN_DIR=${ROOT_DIR}/domains

mkdir -p "${DOMAIN_DIR}"

curl -fsSL \
  -o "$DOMAIN_DIR/geoip-cn.srs" \
  "https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set/geoip-cn.srs"

curl -fsSL \
  -o "$DOMAIN_DIR/geosite-cn.srs" \
  "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-cn.srs"

curl -fsSL \
  -o "$DOMAIN_DIR/geosite-category-ads-all.srs" \
  "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-category-ads-all.srs"

merge_srs_urls "$DOMAIN_DIR/geosite-whitelist.srs" \
    "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-apple.srs" \
    "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-microsoft.srs" \
    "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-google.srs" \
    "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-github.srs" \
    "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-mozilla.srs"

compile_adblock_txt_urls "$DOMAIN_DIR/hagezi-standard.srs" \
  "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/pro.txt" \
  "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/tif.txt" \
  "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/spam-tlds-adblock.txt"

chown -R docker:docker "$DOMAIN_DIR"

EOF

#
# Configs
#
COPY --chown=docker:docker ./opt "${ROOT_DIR}/"

#
# Copy s6 service files
#
COPY --chown=root:root ./s6 /etc/s6-overlay/s6-rc.d/
RUN <<EOF
set -euo pipefail

chmod +x /etc/s6-overlay/s6-rc.d/singbox/run
chmod +x /etc/s6-overlay/s6-rc.d/caddy/run
chmod +x /etc/s6-overlay/s6-rc.d/init/up
EOF

RUN apk del .build-deps

# 443 is needed for obtaining certificates
EXPOSE 443
VOLUME ${ROOT_DIR}/data
ENTRYPOINT ["/init"]