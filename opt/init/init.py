import os
import base64
import subprocess
from typing import Any
import urllib.parse
import jinja2

from pathlib import Path

CONFIG_ROOT = Path("/opt/sonaive")

# BENCHMARK_MANIFEST = {
#     "speedtest_1K.bin": 1,
#     "speedtest_10K.bin": 10,
#     "speedtest_100K.bin": 100,
#     "speedtest_1M.bin": 1024,
#     "speedtest_10M.bin": 10240,
#     "speedtest_100M.bin": 102400,
#     "speedtest_1G.bin": 1048576,
# }

# BENCHMARK_TRUNK_SIZE = 32 * 1024 * 1024 # 32MB

class naive_args:
    host: str
    port: int
    dev: bool
    block_cn: bool
    block_ads: bool
    log_level: str
    default_site: bool
    weblink_prefix : str
    users: dict[str, str]
    userlinks: dict[str, dict[str, str]]

    def __init__(self) -> None:
        self._from_env()

    @staticmethod
    def _str_to_bool(s : str) -> bool:
        return s.lower() == "true".lower()

    @staticmethod
    def _get_env(name: str, default : str, required: bool = False) -> str:
        env = os.getenv(name)
        if env is None:
            if required:
                raise Exception(f'Missing environment variable "{name}".')
            else:
                return default
        return env

    def _populate_v2rayn_links(self) -> None:
        for user, password in self.users.items():
            if user not in self.userlinks:
                self.userlinks[user] = {}
            self.userlinks[user]["v2rayN"] = (
                f"naive+https://{urllib.parse.quote(user)}:{urllib.parse.quote(password)}@{self.host}:{self.port}?"
                "security=tls&"
                "insecure=0&"
                "allowInsecure=0&"
                "type=tcp&"
                "headerType=none#"
                f"{self.host}"
            )

    def _populate_shadowrocket_links(self) -> None:
        for user, password in self.users.items():
            if user not in self.userlinks:
                self.userlinks[user] = {}
            b64 : str = base64.urlsafe_b64encode(f"{user}:{password}@{self.host}:{self.port}".encode("utf-8")).decode()
            self.userlinks[user]["shadowrocket"] = f"http2://{b64}?padding=1&uot=2&tfo=1#{self.host}"

    def _populate_shareable_links(self) -> None:
        self.userlinks = {}
        self._populate_shadowrocket_links()
        self._populate_v2rayn_links()

    def _from_env(self) -> None:
        self.host = self._get_env("HOST", "", required = True)
        self.port = int(self._get_env("PORT", "443"))
        self.block_ads = self._str_to_bool((self._get_env("BLOCK_ADS", "true")))
        self.block_cn = self._str_to_bool((self._get_env("BLOCK_CN", "true")))
        self.block_local = self._str_to_bool((self._get_env("BLOCK_LOCAL", "true")))
        self.weblink_prefix = self._get_env("WEBLINK_PREFIX", "")
        self.log_level = self._get_env("LOG_LEVEL", default="info")
        self.default_site = self._str_to_bool((self._get_env("DEFAULT_SITE", "true")))
        self.dev = self._str_to_bool((self._get_env("DEV", "false")))

        self.users = {}
        i = 0
        while True:
            user_val = self._get_env(f"USER{i}", "").strip()
            # Strict stopping condition: break if userX does not exist
            if len(user_val) == 0:
                if i == 0:
                    raise Exception("Must define at least one user.")
                break

            # Retrieve matching password; defaults to empty string if unset
            pass_val = self._get_env(f"PASS{i}", "").strip()

            if len(pass_val) == 0:
                raise Exception(f"USER{i} has an empty password.")

            self.users[user_val] = pass_val
            i += 1

        self._populate_shareable_links()

    def __str__(self) -> str:
        ret = (
            f"Host: {self.host}\n"
            f"Port: {self.port}\n"
            f"Block CN: {self.block_cn}\n"
            f"Block ADs: {self.block_ads}\n"
            f"Block Local: {self.block_local}\n"
            f"Default Site: {self.default_site}\n"
            f"Weblink Prefix: {self.weblink_prefix}\n"
            f"Log Level: {self.log_level}\n"
            f"Dev: {self.dev}\n"
            f"Users: {self.users}"

        )
        return ret


def caddy_hash_password(
    password : str,
    caddy_bin : Path,
) -> str:
    if not caddy_bin.exists():
        raise FileNotFoundError(f"Caddy binary not found: {caddy_bin}")

    proc = subprocess.run(
        [
            str(caddy_bin),
            "hash-password",
            "--algorithm",
            "bcrypt",
        ],
        input=password + "\n",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )

    if proc.returncode != 0:
        raise Exception(
            f"caddy hash-password failed with exit code {proc.returncode}:\n"
            f"{proc.stderr.strip()}"
        )

    hashed = proc.stdout.strip()

    if not hashed:
        raise Exception("caddy hash-password returned empty output")

    return hashed

# def gen_bench_files(path : Path):
#     rand_trunk = None
#     for filename, size_kb in BENCHMARK_MANIFEST.items():
#         size : int = size_kb * 1024
#         f : Path = path / filename

#         if not f.exists() or f.stat().st_size != size:
#             print(f"\"{f}\" missing or has a wrong size. Generating high-entropy payload @ ({size_kb} KiB)...", end = " ")

#             if rand_trunk is None:
#                 rand_trunk = os.urandom(BENCHMARK_TRUNK_SIZE)

#             full_chunks = size // BENCHMARK_TRUNK_SIZE
#             remainder = size % BENCHMARK_TRUNK_SIZE

#             with open(f, "wb") as file:
#                 for _ in range(full_chunks):
#                             file.write(rand_trunk)
#                 if remainder:
#                     file.write(rand_trunk[:remainder])
#             print("Done!")
#         else:
#             print(f"\"{f}\" exists and has the correct size.")

def process_directory(
    path: Path, vars: dict[str, str], delete_template: bool = True
) -> None:
    for f in os.listdir(path):
        full_path = path / f
        if os.path.isdir(full_path):
            process_directory(full_path, vars, delete_template)
        elif f.endswith(".in"):
            with open(full_path, "r") as sf:
                with open(str(full_path)[:-3], "w") as df:
                    template: jinja2.Template = jinja2.Template(sf.read())
                    expanded : str = template.render(**vars)
                    df.write(expanded)
            if delete_template:
                subprocess.check_call(f"rm {full_path}", shell=True)


def build_users(users: dict[str, str]) -> str:
    ret = ""
    for user, password in users.items():
        ret += f"basic_auth {user} {password}\n"
    return ret

def build_jinja_dict(args: naive_args) -> dict[str, str]:
    jinja_dict : dict[str, Any] = dict()
    jinja_dict["HOST"] = args.host
    jinja_dict["DEV"] = args.dev
    jinja_dict["PORT"] = args.port
    jinja_dict["DEFAULT_SITE"] = args.default_site
    jinja_dict["LOG_LEVEL"] = args.log_level
    jinja_dict["BLOCK_ADS"] = args.block_ads
    jinja_dict["BLOCK_CN"] = args.block_cn
    jinja_dict["BLOCK_LOCAL"] = args.block_local
    jinja_dict["USERS"] = build_users(args.users)
    jinja_dict["WEBLINK_PREFIX"] = args.weblink_prefix

    return jinja_dict

def gen_web_links(path : Path, args: naive_args, template : dict[str, str]) -> str:
    weblinks = ""
    with open(str(CONFIG_ROOT / "caddy" / "weblink.template"), "r") as f:
        weblink_temp : str = f.read()
    for user, links in args.userlinks.items():
        print(f'\n===== User "{user}" =====')
        if len(template["WEBLINK_PREFIX"]) > 0:
            print(f'Weblink @ https://{template["HOST"]}:{template["PORT"]}/{template["WEBLINK_PREFIX"]}/{user}/\n')
        else:
            print('Weblink disabled!\n')

        user_dir : Path = path / user

        weblink_dict : dict[str, str] = template.copy()
        weblink_dict["USER"] = user
        weblink_dict["PASS_HASH"] = caddy_hash_password(args.users[user], CONFIG_ROOT / "caddy" / "caddy")
        temp = jinja2.Template(weblink_temp)
        weblinks += temp.render(**weblink_dict) + "\n"

        for app, link in links.items():
            print(f"{app}:\n{link}")
            app_dir = user_dir / app
            os.makedirs(str(app_dir), exist_ok=True)
            file = app_dir / "link.txt"
            with open(str(file), "w") as f:
                f.write(link + "\n")
            subprocess.check_output(
                f"qrencode -o {str(app_dir / 'qrcode.png')} < {file}", shell=True)
            print(subprocess.check_output(f"qrencode -t ansiutf8 < {file}\n", shell=True).decode())

    return weblinks

def main():
    print("Initializing sonaive...")
    args : naive_args = naive_args()

    print(f"\nConfiguration:\n{str(args)}\n")

    template = build_jinja_dict(args)

    print("Generating weblinks...")
    weblinks = gen_web_links(CONFIG_ROOT / "users", args, template)
    template["WEBLINKS"] = (weblinks if len(args.weblink_prefix) > 0 else "")

    print("Processing config files...")
    process_directory(CONFIG_ROOT, template)

    print("Initialization completed.")

main()
