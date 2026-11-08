#!/usr/bin/env python3
"""Disposable PostgreSQL/PostgREST fixture; no production accounts or Supabase access."""
import argparse
import base64
import hashlib
import hmac
import json
import os
from pathlib import Path
import plistlib
import shutil
import socket
import subprocess
import time
import urllib.request

ROOT = Path(__file__).resolve().parents[5]
HERE = Path(__file__).resolve().parent
STATE = ROOT / "playgrounds/alkkagi/.build/online"
OWNER = hashlib.sha256(str(ROOT).encode()).hexdigest()[:10]
NAMES = {kind: f"alkkagi-{OWNER}-{kind}" for kind in ("db", "rest", "net")}
LABEL = "dev.aingcheck.alkkagi-fixture"
DB_PORT = int(os.environ.get("ALKKAGI_TEST_DB_PORT", "51051"))
API_PORT = int(os.environ.get("ALKKAGI_TEST_API_PORT", "51052"))
BASE_URL = f"http://127.0.0.1:{API_PORT}"
POSTGRES = "postgres@sha256:9a8afca54e7861fd90fab5fdf4c42477a6b1cb7d293595148e674e0a3181de15"
POSTGREST = "postgrest/postgrest@sha256:1347d7552b88f17832912c06afbf7c43209af6eeeb60834b04aae12c9bd9d5cc"
# Public test key and password. These belong only to this disposable loopback fixture.
JWT_SECRET = "alkkagi-local-test-signing-key-only-20261108"
PASSWORD = "alkkagi-local-only"
USERS = {label: f"{digit * 8}-{digit * 4}-4{digit * 3}-8{digit * 3}-{digit * 12}"
         for label, digit in zip("abcd", "1234")}


def run(arguments, *, data=None):
    result = subprocess.run(arguments, input=data, text=True, capture_output=True)
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or result.stdout.strip())
    return result.stdout.strip()


def inspect(kind):
    result = subprocess.run(["docker", "inspect", NAMES[kind]], text=True, capture_output=True)
    if result.returncode:
        return None
    row = json.loads(result.stdout)[0]
    if row["Config"]["Labels"].get(LABEL) != OWNER:
        raise RuntimeError(f"Refusing to reuse or remove an unrelated container: {NAMES[kind]}")
    return row


def sql(source):
    if inspect("db") is None:
        raise RuntimeError("Start the local fixture first")
    return run(["docker", "exec", "-i", NAMES["db"], "psql", "-X", "-q", "-A", "-t",
                "-v", "ON_ERROR_STOP=1", "-U", "postgres"], data=source)


def token(user, role="authenticated"):
    def encode(value):
        return base64.urlsafe_b64encode(json.dumps(value, separators=(",", ":")).encode()).rstrip(b"=")
    header = encode({"alg": "HS256", "typ": "JWT"})
    payload = encode({"sub": USERS[user], "role": role, "exp": int(time.time()) + 86_400})
    unsigned = header + b"." + payload
    signature = base64.urlsafe_b64encode(hmac.new(JWT_SECRET.encode(), unsigned, hashlib.sha256).digest()).rstrip(b"=")
    return (unsigned + b"." + signature).decode()


def wait_until(check, description):
    deadline = time.monotonic() + 25
    while time.monotonic() < deadline:
        try:
            if check():
                return
        except (OSError, RuntimeError):
            pass
        time.sleep(0.25)
    raise RuntimeError(f"Timed out waiting for {description}")


def available(port):
    with socket.socket() as probe:
        try:
            probe.bind(("127.0.0.1", port))
        except OSError as error:
            raise RuntimeError(f"Port {port} is occupied; no automatic port fallback") from error


def start():
    for kind in ("db", "rest"):
        if inspect(kind) is not None:
            raise RuntimeError("Fixture already exists; use status, or stop before starting a fresh fixture")
    available(DB_PORT)
    available(API_PORT)
    STATE.mkdir(parents=True, exist_ok=True)
    run(["docker", "network", "create", "--label", f"{LABEL}={OWNER}", NAMES["net"]])
    run(["docker", "run", "-d", "--name", NAMES["db"], "--network", NAMES["net"],
         "--label", f"{LABEL}={OWNER}", "-p", f"127.0.0.1:{DB_PORT}:5432",
         "-e", f"POSTGRES_PASSWORD={PASSWORD}", POSTGRES])
    wait_until(lambda: "accepting connections" in run(
        ["docker", "exec", NAMES["db"], "pg_isready", "-U", "postgres"]), "PostgreSQL")
    for path in [HERE / "bootstrap.sql", HERE.parent / "20261108160000_alkkagi_physics.sql",
                 HERE.parent / "20261108161000_alkkagi_matches.sql",
                 HERE.parent / "20261108162000_alkkagi_progress.sql"]:
        # Migration files run atomically, matching the documented deployment transaction.
        run(["docker", "exec", "-i", NAMES["db"], "psql", "-X", "-1", "-v", "ON_ERROR_STOP=1", "-U", "postgres"],
            data=path.read_text())
    run(["docker", "run", "-d", "--name", NAMES["rest"], "--network", NAMES["net"],
         "--label", f"{LABEL}={OWNER}", "-p", f"127.0.0.1:{API_PORT}:3000",
         "-e", f"PGRST_DB_URI=postgres://authenticator:{PASSWORD}@{NAMES['db']}:5432/postgres",
         "-e", "PGRST_DB_SCHEMAS=public", "-e", "PGRST_DB_ANON_ROLE=anon",
         "-e", f"PGRST_JWT_SECRET={JWT_SECRET}", POSTGREST])
    wait_until(lambda: urllib.request.urlopen(BASE_URL, timeout=2).status == 200, "PostgREST")
    metadata = {"base_url": BASE_URL, "db_port": DB_PORT, "api_port": API_PORT,
                "names": NAMES, "owner": OWNER, "images": [POSTGRES, POSTGREST]}
    (STATE / "stack.json").write_text(json.dumps(metadata, indent=2) + "\n")
    print(json.dumps(metadata))


def stop():
    for kind in ("rest", "db"):
        if inspect(kind) is not None:
            run(["docker", "rm", "--force", "--volumes", NAMES[kind]])
    result = subprocess.run(["docker", "network", "inspect", NAMES["net"]], text=True, capture_output=True)
    if result.returncode == 0:
        row = json.loads(result.stdout)[0]
        if row.get("Labels", {}).get(LABEL) != OWNER:
            raise RuntimeError("Refusing to remove an unrelated Docker network")
        run(["docker", "network", "rm", NAMES["net"]])
    print("Stopped the local alkkagi fixture")


def apps():
    if inspect("rest") is None:
        raise RuntimeError("Start the local fixture before creating the two test clients")
    package = ROOT / "playgrounds/alkkagi"
    subprocess.run(["swift", "build", "--package-path", str(package), "--product", "AlkkagiPlayground"], check=True)
    binary = Path(run(["swift", "build", "--package-path", str(package), "--show-bin-path"])) / "AlkkagiPlayground"
    for label in "ab":
        name = f"Alkkagi Online {label.upper()}"
        bundle = package / ".build" / f"{name}.app"
        executable = bundle / "Contents/MacOS"
        resources = bundle / "Contents/Resources"
        executable.mkdir(parents=True, exist_ok=True)
        resources.mkdir(parents=True, exist_ok=True)
        shutil.copy2(binary, executable / "AlkkagiPlayground")
        info = {"CFBundleIdentifier": f"dev.aingcheck.alkkagi.online.{label}", "CFBundleName": name,
                "CFBundleExecutable": "AlkkagiPlayground", "CFBundlePackageType": "APPL",
                "NSHighResolutionCapable": True, "LSMinimumSystemVersion": "14.0"}
        with (bundle / "Contents/Info.plist").open("wb") as stream:
            plistlib.dump(info, stream)
        configuration = resources / "AlkkagiOnlinePreview.json"
        configuration.write_text(json.dumps({"baseURL": BASE_URL, "accessToken": token(label),
                                             "title": f"알까기 온라인 테스트 {label.upper()}"}, ensure_ascii=False))
        configuration.chmod(0o600)
        print(bundle)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["start", "stop", "status", "apps"])
    command = parser.parse_args().command
    if command == "start":
        start()
    elif command == "stop":
        stop()
    elif command == "apps":
        apps()
    else:
        print(json.dumps({kind: bool(inspect(kind)) for kind in ("db", "rest")}))
