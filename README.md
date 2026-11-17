# sonaive: painless NaïveProxy in Docker!
[![Build](https://git.quacker.org/d/sonaive/badges/workflows/build.yml/badge.svg?branch=master&label=build)](https://git.quacker.org/d/sonaive/actions)

## What(who) is sonaive?
`sonaive` is the NaïveProxy frontend of a small set of Docker containers that offers easy 5-minute setups and braindead configurations for [NaïveProxy](https://github.com/klzgrad/naiveproxy). It terminates TLS, serves the proxy, and forwards everything else to a decoy site and an upstream filtering proxy.

## Features
- A clean, simple deployment built using [Caddy](https://github.com/caddyserver/caddy) w/ [forwardproxy@naïve](https://github.com/klzgrad/forwardproxy).
- Automatic certificate management.
- Blocks CN traffic and ADs using [HaGeZi](https://github.com/hagezi/dns-blocklists) Pro(++), TIF and Spam TLDs, via the bundled `filter` container.
- An optional decoy site served by a separate container using [reputable sources](https://github.com/torvalds/linux).
- Automatic QR code and link generation for popular APPs, printed to the container log.
- Automatic weekly builds.

## Quickstart
1. You can start with the example `docker-compose.yml` from this repo.
2. Adjust environment variables:
    - `HOST`: the hostname of the server. `REQUIRED`.
    - `PORT`: the public port you expose. The container internally always use port 443 for NaïveProxy and 80 for ACME challenges. To change the NaïveProxy port, map a different host port to 443 and set `PORT` to the same value. Port 80 must be identity mapped for certificate generation. `Optional, default = 443`.
    - `SITE_URL`: address of the decoy site backend, e.g. `decoy:3000`. When unset, all non-proxied requests receive a `403` response. `Optional, default = ""`.
    - `UPSTREAM_URL`: upstream http proxy address the proxy chain forwards to, e.g. `filter:1080`. When unset, requests are dialed directly. `Optional, default = ""`.
    - `USERX`: an arbitrary number of usernames starting from X=0, see the `docker-compose.yml` for examples. `REQUIRED: at least one user.`.
    - `PASSX`: the corresponding password for USERX. `REQUIRED: one per user`.
    - `LOG_LEVEL`: the verbosity of logging, one of `info`, `warn`, `error`, `debug`, `panic` and `fatal`. `Optional, default = warn`.
    - `SELF_SIGN`: use Caddy's internal CA and a self signed certificate instead of ACME. Only the literal `true` and `false` are recognized. `Optional, default = false`.
3. `docker compose up -d`
4. Check the container log using `docker logs` for per user shareable links and QR codes for [v2rayN](https://github.com/2dust/v2rayn) and [shadowrocket](https://shadowlaunch.com/).
5. Visit your server in the browser to see your decoy site (or a `403` if `SITE_URL` is unset), and test your NaïveProxy connections.

## Docker volume
Bind mount a local folder to `/opt/sonaive/data` to persist settings and certificates across container reboots. Make sure the local folder is owned by or accessible to uid 1000 and gid 1000.

sonaive stores Caddy's generated configuration, data and certificates under `caddy`.

It also writes per-user `link.txt` and `qrcode.png` files under `/opt/sonaive/users`, which is outside the persisted volume. The same links and QR codes are printed to the container log on every start.

## How to update?
- `docker compose down`
- `docker compose pull`
- `docker compose up -d`

## Notes
- It may take a while to generate the certificates when running for the first time. Follow `docker logs` for more details.
- If you need to turn on QUIC/HTTP3 support, simply expose UDP for the same TCP NaïveProxy port.

## Troubleshooting
- Use `docker logs` to debug Caddy startup failures, and the logs of the `filter` and `decoy` containers for their own.
- If you receive a warning about `"failed to sufficiently increase receive buffer size"`, you can simply ignore the warning if you do not use QUIC/HTTP3. Otherwise follow the instructions [here](https://github.com/quic-go/quic-go/wiki/UDP-Buffer-Sizes). Note that these options must be set on *HOST*. You can use `/etc/sysctl.conf` to persist the settings across reboots.
- If you have trouble visiting certain sites and are sure the client is configured correctly, try relaxing `BLOCK_ADS` on the `filter` container. Disabling `BLOCK_CN` is not recommended as it might leak VPS's IPs.