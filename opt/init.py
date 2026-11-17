import base64
import os
import subprocess
import urllib.parse
from pathlib import Path
from typing import Any

import jinja2

CONFIG_ROOT = Path("/opt/sonaive")

class naive_args:
    host: str
    port: int
    self_sign: bool
    log_level: str
    site_url: str
    upstream_url: str
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
                raise RuntimeError(f'Missing environment variable "{name}".')
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
            b64 : str = base64.urlsafe_b64encode(f"{user}:{password}@{self.host}:{self.port}".encode()).decode()
            self.userlinks[user]["shadowrocket"] = f"http2://{b64}?padding=1&uot=2&tfo=1#{self.host}"

    def _populate_shareable_links(self) -> None:
        self.userlinks = {}
        self._populate_shadowrocket_links()
        self._populate_v2rayn_links()

    def _from_env(self) -> None:
        self.host = self._get_env("HOST", "", required = True)
        self.port = int(self._get_env("PORT", "443"))
        self.log_level = self._get_env("LOG_LEVEL", default="warn")
        self.site_url = self._get_env("SITE_URL", "")
        self.upstream_url = self._get_env("UPSTREAM_URL", "")
        self.self_sign = self._str_to_bool(self._get_env("SELF_SIGN", "false"))

        self.users = {}
        i = 0
        while True:
            user_val = self._get_env(f"USER{i}", "").strip()
            # Strict stopping condition: break if userX does not exist
            if len(user_val) == 0:
                if i == 0:
                    raise RuntimeError("Must define at least one user.")
                break

            # Retrieve matching password; defaults to empty string if unset
            pass_val = self._get_env(f"PASS{i}", "").strip()

            if len(pass_val) == 0:
                raise RuntimeError(f"USER{i} has an empty password.")

            self.users[user_val] = pass_val
            i += 1

        self._populate_shareable_links()

    def __str__(self) -> str:
        ret = (
            f"HOST: {self.host}\n"
            f"PORT: {self.port}\n"
            f"SITE_URL: {self.site_url}\n"
            f"UPSTREAM_URL: {self.upstream_url}\n"
            f"LOG_LEVEL: {self.log_level}\n"
            f"SELF_SIGN: {self.self_sign}\n"
            f"USERS: {self.users}"
        )
        return ret

def process_directory(
    path: Path, vars: dict[str, str], delete_template: bool = True
) -> None:
    for f in os.listdir(path):
        full_path = path / f
        if os.path.isdir(full_path):
            process_directory(full_path, vars, delete_template)
        elif f.endswith(".in"):
            with open(full_path, "r") as sf, open(str(full_path)[:-3], "w") as df:
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
    jinja_dict : dict[str, Any] = {}
    jinja_dict["HOST"] = args.host
    jinja_dict["SELF_SIGN"] = args.self_sign
    jinja_dict["PORT"] = args.port
    jinja_dict["SITE_URL"] = args.site_url
    jinja_dict["UPSTREAM_URL"] = args.upstream_url
    jinja_dict["LOG_LEVEL"] = args.log_level
    jinja_dict["USERS"] = build_users(args.users)

    return jinja_dict

def gen_shareable_links(path: Path, args: naive_args) -> None:
    for user, links in args.userlinks.items():
        print(f'\n===== User "{user}" =====')
        user_dir : Path = path / user

        for app, link in links.items():
            print(f"{app}:\n{link}")
            app_dir = user_dir / app
            os.makedirs(str(app_dir), exist_ok=True)
            file = app_dir / "link.txt"
            with open(str(file), "w") as f:
                f.write(link + "\n")
            subprocess.check_output(
                f"qrencode -o {app_dir / 'qrcode.png'!s} < {file}", shell=True)
            print(subprocess.check_output(f"qrencode -t ansiutf8 < {file}\n", shell=True).decode())

def main():
    print("Initializing sonaive...")
    args : naive_args = naive_args()

    print(f"\nConfiguration:\n{args!s}\n")

    template = build_jinja_dict(args)

    print("Generating shareable links...")
    gen_shareable_links(CONFIG_ROOT / "users", args)

    print("Processing config files...")
    process_directory(CONFIG_ROOT, template)

    print("Initialization completed.")

main()
