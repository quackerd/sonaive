# sonaive: painless NaïveProxy in Docker!
[![Build](https://git.quacker.org/d/sonaive/badges/workflows/build.yml/badge.svg?branch=master&label=build)](https://git.quacker.org/d/sonaive/actions)

## What(who) is sonaive?
`sonaive` is a single Docker container that offers easy 5-minute setups and braindead configurations for [NaïveProxy](https://github.com/klzgrad/naiveproxy).

## Features
- A clean, simple single docker container deployment built using [Caddy](https://github.com/caddyserver/caddy) w/ [forwardproxy@naïve](https://github.com/klzgrad/forwardproxy) and [sing-box](https://github.com/sagernet/sing-box).
- Automatic certificate management.
- Block CN traffic using [IPs](https://github.com/Loyalsoldier/geoip) and [domains](https://github.com/Loyalsoldier/v2ray-rules-dat).
- Block ADs using [HaGeZi](https://github.com/hagezi/dns-blocklists) Multi PRO and TIF.
- Default static site using [reputable sources](https://github.com/torvalds/linux).
- Automatic QR code and link generation for popular APPs and accessible via the website.
- Automatic weekly builds.

## Quickstart
1. You can start with the example `docker-compose.yml` from this repo.
2. There are two tags to use `latest` and `latest-full`. `latest-full` adds two source code tarball downloads to `latest`, which adds ~300MiB to the image. Use `latest-full` if you think it justifies heavy traffic better.
3. Adjust environment variables:
    - `HOST`: the hostname of the server. `REQUIRED`.
    - `PORT`: the public port you expose. The container internally always use port 443 for NaïveProxy and 80 for ACME challenges. To change the NaïveProxy port, simply map a different host port to 443. Port 80 must be identity mapped for certificate generation. `Optional, default = 443`.
    - `BLOCK_CN`: blocks all connections to CN IPs & domains. `Optional, default = true`.
    - `BLOCK_ADS`: blocks ad domains, one of `none`, `basic` (geosite:category-ads-all), `standard` (HaGeZi Pro + TIF + most abused TLDs). `Optional, default = standard`.
    - `BLOCK_LOCAL`: blocks private IPs. `Optional, default = true`.
    - `DEFAULT_SITE`: Use the default generated site. `Optional, default = true`.
    - `USERX`: An arbitrary number of usernames starting from X=0, see the `docker-compose.yml` for examples. `REQUIRED: at least one user.`.
    - `PASSX`: The corresponding password for USERX. `REQUIRED: one per user`.
    - `WEBLINK_PREFIX`: The url prefix / sub-url for accessing the generated links and QR codes per user. *Must contain no leading or trailing slashes*. Each user's links can be accessed at [https://$HOST:$PORT/$WEBLINK_PREFIX/$USER](https://$HOST:$PORT/$WEBLINK_PREFIX/$USER). Users must authenticate themselves using their passwords. This takes precedence over the static site being served, e.g. overwriting the same sub-url. `Optional, default is disabled.`.
    - `LOG_LEVEL`: the verbosity of logging, one of `info`, `warn`, `error` and `debug`. `Optional, default = warn`.
    - `DEV`: development mode (auto generate self signed certificates). `Optional, default = false`.
4. `docker compose up -d`
5. Check the container log using `docker logs` for per user shareable links and QR codes for [v2rayN](https://github.com/2dust/v2rayn) and [shadowrocket](https://shadowlaunch.com/).
6. Visit your server in the browser and test your NaïveProxy connections.

## Docker volume
Bind mount a local folder to `/opt/sonaive/data` to persist settings and certificates across container reboots. Make sure the local folder is owned by or accessible to uid 1000 and gid 1000.

sonaive automatically generates four subfolders:
- `caddy` contains Caddy generated files and logs such as certificates.
- `singbox` contains sing-box logs and cache.
- `users` contains text files and images of per user shareable links.
- `www` contains the custom static website files if `DEFAULT_SITE` is set to false.

## How to update?
- `docker compose down`
- `docker compose pull`
- `docker compose up -d`

## Notes
- It may take a while to generate the certificates when running for the first time. Please refer to `caddy/logs/system.log` for more details.
- If you need to turn on QUIC/HTTP3 support, simply expose UDP for the same TCP NaïveProxy port.

## Troubleshooting
- Use docker logs to debug Caddy/sing-box startup failures and individual application logs to debug the behaviors.
- If you receive a warning about `"failed to sufficiently increase receive buffer size"`, you can simply ignore the warning if you do not use QUIC/HTTP3. Otherwise follow the instructions [here](https://github.com/quic-go/quic-go/wiki/UDP-Buffer-Sizes). Note that these options must be set on *HOST*. You can use `/etc/sysctl.conf` to persist the settings across reboots.
- If you have trouble visiting certain sites and are sure the client is configured correctly, try disabling `BLOCK_CN` or `BLOCK_ADS`.