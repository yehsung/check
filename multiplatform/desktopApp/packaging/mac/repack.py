#!/usr/bin/env python3
"""아잉체크 Windows 운영 판 — 맥에서 desktopApp jar 하나만 바꿔 끼워 다시 싼다(W6-b2, package.md §5 W6-b2 · 길 (나) 변형 B).

repack.sh 가 python3 -I 로 부른다(표준 라이브러리만 · 판정 규칙의 정본은 ../release_win.py — 두 벌 금지).
흐름(build): 입력 판정(종료 2) → CI 레이아웃 = 영수증 → 봉인 Gradle 로 desktopApp jar 재빌드(운영 값은 환경 변수로만)
  → jar_diff 가 generated/ProdConfig 계열만 → 같은 이름으로 교체 → makemsix pack(x64·arm64) → makemsix unpack(블록맵 검증)
  → 바꾼 jar 를 뺀 runtime+app 지문 = CI 영수증 → repack.json · (--dry 가 아니면) 장부 versions.tsv 한 줄.
종료 코드: 0 초록 · 1 빌드·판정 실패 · 2 입력 거부.

맥 출시 규약 번호(★, package.md §2 — release_win.py 머리와 같은 번호):
  ★1 종료 코드를 믿지 않는다 — makemsix·Gradle 이 0 이어도 산출물 안 값(jar 항목·풀어 낸 파일 sha256)으로 판정한다.
  ★2 Windows build 는 맥과 다른 정수 축(version.properties windowsBuild) — 장부 최댓값보다 커야 한다.
  ★3 값은 argv 배열로(셸 보간 없음). anon 키는 argv·로그·장부·영수증에 싣지 않는다 — Gradle 에는 환경 변수
     ORG_GRADLE_PROJECT_aingcheck.prod.* 로만. 자식 명령줄은 전부 cmdlines.jsonl 에 남기고 키 0 을 단언한다.
  ★5 운영 host 는 장부·영수증에 해시 8자리(.invalid 만 글자 그대로 — release_win.prod_host_for_receipt).
  ★6 서버를 부르지 않는다. publish-sql 은 SQL 한 줄을 찍기만 한다(실행은 조정자가 사용자와 함께).
"""
from __future__ import annotations

import sys

sys.dont_write_bytecode = True  # -I 는 PYTHONDONTWRITEBYTECODE 를 무시한다 — __pycache__ 를 저장소에 흘리지 않는다
import base64  # noqa: E402
import hashlib  # noqa: E402
import json  # noqa: E402
import os  # noqa: E402
import shutil  # noqa: E402
import subprocess  # noqa: E402
import time  # noqa: E402
import zipfile  # noqa: E402
from pathlib import Path, PurePosixPath  # noqa: E402
from urllib.parse import urlparse  # noqa: E402

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))  # -I 는 스크립트 폴더를 sys.path 에 넣지 않는다
import release_win as rw  # noqa: E402

# 자기 시험만 가짜 저장소 뿌리·봉인 없음·가짜 makemsix 를 쓴다(repack_selftest.py 가 AINGCHECK_REPACK_SELFTEST=1 로 부른다).
SELFTEST = os.environ.get("AINGCHECK_REPACK_SELFTEST") == "1"
MP = Path(os.environ["AINGCHECK_REPACK_MP"]).resolve() if SELFTEST and os.environ.get("AINGCHECK_REPACK_MP") else rw.MP
REPO = MP.parent
PACKAGING = MP / "desktopApp" / "packaging"
LEDGER = PACKAGING / "versions.tsv"
# 다시 싸는 동안 더러워도 되는 자리(이 갈래 소유 — jar 입력이 아니다). 그 밖이 더러우면 "HEAD 의 jar" 라는 전제가 깨진다.
OWN_DIRTY_OK = ("multiplatform/desktopApp/packaging/mac/", "multiplatform/desktopApp/packaging/versions.tsv")
PROD_KEYS = ("aingcheck.prod.supabaseUrl", "aingcheck.prod.supabaseAnonKey")
SECRET_MARKERS = ("service" + "_role", "sb" + "_secret_", "BEGIN " + "PRIVATE KEY")  # build-logic FORBIDDEN_SECRET_MARKERS 와 같은 뜻(입력 단계에서 먼저 거른다)
PROD_CONFIG_PREFIX = rw.GENERATED_PREFIX + "ProdConfig"
INVALID_DEFAULT_URL = b"https://aingcheck.invalid"
# makemsix 는 저장소 밖에 소스로 짓는다(repack.sh tools). 커밋과 바이너리 sha256 을 고정한다(arm64 맥, makemac.sh -arch arm64 --pack).
MAKEMSIX_COMMIT = "25a65f5c1690930813bcc10cdf1d59fa865f2bb1"
MAKEMSIX_HOME = Path.home() / ".aing-check-tools" / f"msix-packaging-{MAKEMSIX_COMMIT[:8]}"
MAKEMSIX_PIN = {
    "bin/makemsix": "2f7306ecb72cf2634b1c0afdf1d6e40293496c9c5303b2898e13f76aa429e70f",
    "lib/libmsix.dylib": "c861e56ea109fadbe3d42bcd537d43ccab23e937459c9919e4d63077c8f1c44e",
}
# 풀어 낸 패키지에서 레이아웃에 없어도 되는 파일(makemsix 가 만든다).
PACKAGE_ONLY = {"AppxBlockMap.xml", "[Content_Types].xml", "AppxSignature.p7x"}


class Refuse(Exception):
    """입력 거부 — 종료 2."""


class Fail(Exception):
    """빌드·판정 실패 — 종료 1."""


# ---- 입력 ------------------------------------------------------------------------------------------

def read_prod_config(path: str) -> dict:
    """Java properties(저장소 밖). 키는 Gradle 속성 이름 그대로 두 개 — 하나라도 없거나 비면 거부(종료 2)."""
    p = Path(path)
    if not p.is_file():
        raise Refuse(f"--prod-config 파일이 없다: {p}")
    props = rw.read_props(p)
    unknown = sorted(set(props) - set(PROD_KEYS))
    if unknown:
        raise Refuse(f"--prod-config 에 모르는 키: {unknown}(받는 키 {list(PROD_KEYS)})")
    missing = [k for k in PROD_KEYS if not props.get(k, "").strip()]
    if missing:
        raise Refuse(f"운영 값이 없다: {missing}")
    url, key = props[PROD_KEYS[0]].strip(), props[PROD_KEYS[1]].strip()
    bad = lambda s: any(c.isspace() or c in "\"'\\$`" for c in s)  # noqa: E731
    if not url.startswith("https://") or bad(url) or not urlparse(url).hostname:
        raise Refuse("aingcheck.prod.supabaseUrl 은 공백·따옴표 없는 https:// 주소여야 한다")
    if bad(key):
        raise Refuse("aingcheck.prod.supabaseAnonKey 에 공백·따옴표가 있다")
    payload = ""
    part = key.split(".")[1] if key.count(".") >= 2 else ""
    if part:
        try:
            payload = base64.urlsafe_b64decode(part + "=" * (-len(part) % 4)).decode("utf-8", "replace")
        except (ValueError, UnicodeError):
            payload = ""
    if any(m in key or m in payload for m in SECRET_MARKERS):
        raise Refuse("anon 키 자리에 비밀 키 표식이 있다 — anon 키만 넣는다")
    return {"url": url, "key": key, "host": urlparse(url).hostname.lower()}


def find_ci(ci_dir: Path, arch: str) -> tuple[Path, Path]:
    zips = sorted(ci_dir.rglob(f"AingCheck_*_{arch}.layout.zip"))
    receipts = sorted(ci_dir.rglob(f"AingCheck_*_{arch}.receipt.json"))
    if len(zips) != 1 or len(receipts) != 1:
        raise Refuse(f"{arch}: CI 산출물에 레이아웃 zip·영수증이 하나씩이어야 한다(zip {len(zips)} · 영수증 {len(receipts)})")
    return zips[0], receipts[0]


def git(*args: str) -> str:
    return subprocess.run(["git", "-C", str(REPO), *args], check=True, capture_output=True, text=True).stdout


def dirty_outside_own() -> list[str]:
    raw = git("status", "--porcelain=v1", "-z", "--untracked-files=all")
    out, items = [], raw.split("\0")
    i = 0
    while i < len(items):
        item = items[i]
        i += 1
        if not item:
            continue
        status, path = item[:2], item[3:]
        if status[0] in "RC":
            i += 1  # 옛 이름
        if not path.startswith(OWN_DIRTY_OK):
            out.append(path)
    return out


def preflight(a) -> dict:
    prod = read_prod_config(a.prod_config)
    if a.identity == "dev":
        if not a.dry:
            raise Refuse("dev 신원은 리허설(--dry)만 — 장부에 오르는 판은 store 신원")
        if not prod["host"].endswith(".invalid"):
            raise Refuse("dev 신원 패키지에 운영 host 를 싣지 않는다(.invalid 가짜 값만)")
    elif not a.dry and prod["host"].endswith(".invalid"):
        raise Refuse("장부에 오르는 판에 .invalid host — 운영 값이 아니다")
    try:
        identity = rw.load_identity(a.identity, PACKAGING / "identity")
        versions = rw.read_versions(MP / "version.properties")
    except (ValueError, KeyError, OSError) as e:
        raise Refuse(str(e)) from e
    arches = [x for x in a.arch.split(",") if x]
    if not arches or any(x not in rw.ARCHES for x in arches) or len(set(arches)) != len(arches):
        raise Refuse(f"--arch 는 {','.join(rw.ARCHES)} 중에서: {a.arch!r}")
    ci = {}
    for arch in arches:
        zpath, rpath = find_ci(Path(a.ci), arch)
        r = json.loads(rpath.read_text(encoding="utf-8-sig"))
        if r.get("schema") != rw.SCHEMA or r.get("arch") != arch:
            raise Refuse(f"{rpath.name}: schema·arch 가 {rw.SCHEMA}·{arch} 가 아니다")
        ci[arch] = {"zip": zpath, "receipt": r}
    keys = ("gitSha", "buildTimeUtc", "windowsBuild", "windowsVersion", "msixVersion")
    first = ci[arches[0]]["receipt"]
    for arch in arches[1:]:
        if any(ci[arch]["receipt"].get(k) != first.get(k) for k in keys):
            raise Refuse("아키텍처 영수증의 gitSha·buildTime·build·version 이 서로 다르다")
    if not rw.GIT_SHA.match(str(first.get("gitSha", ""))):
        raise Refuse("영수증 gitSha 가 40자 소문자 hex 가 아니다")
    if not first.get("buildTimeUtc") or first["buildTimeUtc"] == "dev":
        raise Refuse("영수증 buildTimeUtc 가 비었거나 기본값이다")
    head = git("rev-parse", "HEAD").strip()
    if first["gitSha"] != head:
        raise Refuse(f"영수증 gitSha {first['gitSha'][:12]} ≠ HEAD {head[:12]} — 그 커밋을 꺼내 다시 싼다")
    dirty = dirty_outside_own()
    if dirty:
        raise Refuse(f"작업 트리가 더럽다(packaging/mac·versions.tsv 밖): {dirty[:5]}")
    if (int(first["windowsBuild"]), first["windowsVersion"]) != (versions["windowsBuild"], versions["windowsVersion"]):
        raise Refuse(f"영수증 build·version {first['windowsBuild']}·{first['windowsVersion']} ≠ version.properties")
    if first.get("msixVersion") != versions["msixVersion"]:
        raise Refuse("영수증 msixVersion ≠ version.properties")
    ledger_text = LEDGER.read_text(encoding="utf-8") if LEDGER.is_file() else ""
    if not rw.ledger_next_ok(versions["windowsBuild"], ledger_text):  # ★2
        raise Refuse(f"windowsBuild {versions['windowsBuild']} ≤ 장부(versions.tsv) 최댓값 — version.properties 를 올린다")
    out = Path(a.out)
    if out.exists() and any(out.iterdir()):
        raise Refuse(f"--out 이 비어 있지 않다: {out}")
    makemsix = check_makemsix(a.makemsix)
    return {"prod": prod, "identity": identity, "versions": versions, "arches": arches, "ci": ci,
            "first": first, "out": out, "makemsix": makemsix}


def check_makemsix(path: str | None) -> dict:
    exe = Path(path) if path else MAKEMSIX_HOME / "bin" / "makemsix"
    if not exe.is_file():
        raise Refuse(f"makemsix 가 없다: {exe} — repack.sh tools 로 짓는다")
    if SELFTEST:
        return {"path": str(exe), "commit": "selftest", "sha256": rw.sha256_file(exe)}
    home = exe.parent.parent
    got = {rel: rw.sha256_file(home / rel) if (home / rel).is_file() else "missing" for rel in MAKEMSIX_PIN}
    if got != MAKEMSIX_PIN:
        raise Refuse(f"makemsix 지문이 고정값과 다르다: {got}")
    return {"path": str(exe), "commit": MAKEMSIX_COMMIT, "sha256": got["bin/makemsix"]}


# ---- 자식 명령(★3) -----------------------------------------------------------------------------------

class Runner:
    def __init__(self, out: Path, secret: str):
        self.log = out / "cmdlines.jsonl"
        self.secret = secret

    def run(self, argv: list[str], *, env: dict | None = None, cwd: Path | None = None, stdout: Path) -> int:
        if any(self.secret and self.secret in str(x) for x in argv):
            raise Fail("자식 명령줄에 anon 키가 실렸다 — 환경 변수로만 넘긴다")
        with open(self.log, "a", encoding="utf-8") as f:
            f.write(json.dumps({"argv": [str(x) for x in argv], "cwd": str(cwd or "")}, ensure_ascii=False) + "\n")
        with open(stdout, "ab") as f:
            return subprocess.run([str(x) for x in argv], env=env, cwd=cwd, stdout=f, stderr=subprocess.STDOUT).returncode


def gradle_argv(a, first: dict) -> list[str]:
    seal = [] if SELFTEST and os.environ.get("AINGCHECK_REPACK_SEAL") == "none" else \
        ["/usr/bin/sandbox-exec", "-f", str(MP / "scripts" / "seal.sb")]
    # gradlew 는 '#!/bin/sh' — 점이 든 환경 변수 이름을 자식에게 넘기도록 bash 로 부른다(release_tool.py exec-gradle 선례).
    argv = [*seal, "/bin/bash", str(MP / "gradlew"), "--offline", "--no-daemon"]
    if a.gradle_project_cache:
        argv += ["--project-cache-dir", a.gradle_project_cache]
    return argv + ["-Paingcheck.desktop.releaseAssembly=true", f"-Paingcheck.buildTime={first['buildTimeUtc']}",
                   f"-Paingcheck.gitSha={first['gitSha']}", ":desktopApp:jar"]


def gradle_env(prod: dict) -> dict:
    env = {k: v for k, v in os.environ.items() if not k.startswith("ORG_GRADLE_PROJECT_aingcheck.")}
    env["AINGCHECK_NETWORK_SEALED"] = "1"
    env["ORG_GRADLE_PROJECT_" + PROD_KEYS[0]] = prod["url"]
    env["ORG_GRADLE_PROJECT_" + PROD_KEYS[1]] = prod["key"]
    return env


# ---- 판정 -----------------------------------------------------------------------------------------

def safe_extract(zpath: Path, dest: Path) -> None:
    with zipfile.ZipFile(zpath) as z:
        for info in z.infolist():
            name = PurePosixPath(info.filename.replace("\\", "/"))
            if name.is_absolute() or ".." in name.parts:
                raise Fail(f"{zpath.name}: 밖으로 나가는 항목 {info.filename!r}")
        z.extractall(dest)


def tree_digest(root: Path) -> dict:
    return {p.relative_to(root).as_posix(): rw.sha256_file(p) for p in sorted(root.rglob("*")) if p.is_file()}


def fingerprint(files: dict, skip: str) -> str:
    """runtime/·app/ 아래(바꾼 jar 제외)의 경로·sha256 목록 지문."""
    lines = [f"{p}\t{h}" for p, h in sorted(files.items()) if p.split("/")[0] in ("runtime", "app") and p != skip]
    return hashlib.sha256("\n".join(lines).encode("utf-8")).hexdigest()


def judge_jar(ci_jar: Path, mac_jar: Path, prod: dict) -> dict:
    d = rw.jar_diff(ci_jar, mac_jar)
    d["prodOnly"] = bool(d["changed"]) and all(n.startswith(PROD_CONFIG_PREFIX) for n in d["changed"])
    with zipfile.ZipFile(mac_jar) as z:
        prod_cls = b"".join(z.read(n) for n in z.namelist() if n.startswith(PROD_CONFIG_PREFIX) and n.endswith(".class"))
    d["prodValues"] = (prod["url"].encode() in prod_cls and prod["key"].encode() in prod_cls
                       and INVALID_DEFAULT_URL not in prod_cls)
    d["ok"] = d["ok"] and d["prodOnly"] and d["prodValues"]
    return d


def judge_unpacked(receipt: dict, unpacked: dict, mac_jar_sha: str, manifest_from_ci: bool) -> dict:
    """★1 풀어 낸 패키지 = CI 레이아웃(영수증) — 바꾼 jar 만 맥 jar, 매니페스트는 신원에 따라."""
    jar = receipt["appJar"]["name"]
    want = {f["path"]: f["sha256"] for f in receipt["files"]}
    problems = []
    for path, sha in want.items():
        if path == jar:
            if unpacked.get(path) != mac_jar_sha:
                problems.append(f"{path}: 바꾼 jar 가 아니다")
        elif path == "AppxManifest.xml" and not manifest_from_ci:
            if path not in unpacked:
                problems.append("AppxManifest.xml 이 없다")
        elif unpacked.get(path) != sha:
            problems.append(f"{path}: {'없다' if path not in unpacked else 'sha256 다름'}")
    extra = sorted(p for p in unpacked if p not in want and p not in PACKAGE_ONLY)
    problems += [f"{p}: 레이아웃에 없는 파일" for p in extra]
    fp_ci, fp_mac = fingerprint(want, jar), fingerprint(unpacked, jar)
    if fp_ci != fp_mac:
        problems.append("runtime+app 지문이 다르다")
    return {"ok": not problems, "problems": problems[:20], "fingerprint": fp_mac[:16], "ciFingerprint": fp_ci[:16],
            "files": len(unpacked)}


def extract_layout(ci: dict, layout: Path, arch: str) -> Path:
    """★1 CI 레이아웃 zip 을 풀고, 풀린 파일이 영수증 files(경로·sha256)와 정확히 같은지 본다."""
    safe_extract(ci["zip"], layout)
    if tree_digest(layout) != {f["path"]: f["sha256"] for f in ci["receipt"]["files"]}:
        raise Fail(f"{arch}: CI 레이아웃 zip 이 영수증 files 와 다르다")
    return layout


def pack_verify(runner: "Runner", exe: str, layout: Path, receipt: dict, mac_jar: Path, mac_sha: str, identity: dict,
                versions: dict, arch: str, out: Path) -> dict:
    """jar 교체 → (신원이 다르면 매니페스트 다시 그림) → makemsix pack → unpack(블록맵 검증) → 영수증과 대조."""
    shutil.copyfile(mac_jar, layout / receipt["appJar"]["name"])  # 같은 이름으로 교체(AingCheck.cfg 의 classpath 그대로)
    manifest_from_ci = identity["mode"] == receipt["identity"]["mode"] and identity["name"] == receipt["identity"]["name"]
    if not manifest_from_ci:
        tpl = (PACKAGING / "AppxManifest.template.xml").read_text(encoding="utf-8")
        (layout / "AppxManifest.xml").write_text(rw.render_manifest(tpl, identity, versions["msixVersion"], arch),
                                                 encoding="utf-8")
    msix = out / f"AingCheck_{versions['windowsVersion']}_{arch}.msix"
    log = out / f"makemsix-{arch}.log"
    rc_pack = runner.run([exe, "pack", "-d", str(layout), "-p", str(msix)], stdout=log)
    unpacked = out / arch / "unpacked"
    rc_unpack = runner.run([exe, "unpack", "-p", str(msix), "-d", str(unpacked), "-ss"], stdout=log)
    if not msix.is_file() or not unpacked.is_dir():  # ★1 종료 코드 대신 산출물
        raise Fail(f"{arch}: makemsix 가 패키지·풀기 결과를 남기지 않았다(rc {rc_pack}·{rc_unpack}) — {log.name}")
    j = judge_unpacked(receipt, tree_digest(unpacked), mac_sha, manifest_from_ci)
    j["rc"] = [rc_pack, rc_unpack]
    if rc_unpack != 0:  # 블록맵 검증 실패는 unpack 이 0 이 아닌 것으로만 드러난다 — 파일 대조와 함께 둘 다 본다
        j["ok"] = False
        j["problems"].insert(0, f"makemsix unpack rc={rc_unpack}(블록맵 검증)")
    if not j["ok"]:
        raise Fail(f"{arch}: 풀어 낸 패키지가 CI 레이아웃과 다르다: {j['problems'][:5]}")
    return {"msix": msix.name, "sha256": rw.sha256_file(msix), "bytes": msix.stat().st_size, "unpack": j}


def cmd_pack(a) -> int:
    """다시 싸기의 뒷몫만(리허설): 주어진 jar 가 CI jar 와 허용 목록 밖 차이가 없을 때 dev 신원 그대로 x64·arm64 를
    싸고 풀어 대조한다. 운영 값·장부·Gradle 없음 — 맥에서 재현한 jar 로 makemsix 길을 실측할 때 쓴다."""
    out = Path(a.out)
    if out.exists() and any(out.iterdir()):
        raise Refuse(f"--out 이 비어 있지 않다: {out}")
    exe = check_makemsix(a.makemsix)["path"]
    out.mkdir(parents=True, exist_ok=True)
    runner = Runner(out, "")
    mac_jar = Path(a.jar)
    mac_sha = rw.sha256_file(mac_jar)
    report = {"schema": "aingcheck-windows-mac-pack/1", "ok": False, "macJar": {"sha256": mac_sha}, "arches": {}}
    for arch in [x for x in a.arch.split(",") if x]:
        zpath, rpath = find_ci(Path(a.ci), arch)
        receipt = json.loads(rpath.read_text(encoding="utf-8-sig"))
        if receipt.get("schema") != rw.SCHEMA or receipt.get("identity", {}).get("mode") != "dev":
            raise Refuse(f"{rpath.name}: {rw.SCHEMA} dev 영수증이 아니다")
        layout = extract_layout({"zip": zpath, "receipt": receipt}, out / arch / "layout", arch)
        d = rw.jar_diff(layout / receipt["appJar"]["name"], mac_jar)
        report["arches"][arch] = {"jarDiff": d}
        if not d["ok"]:
            raise Fail(f"{arch}: jar 가 허용 목록 밖에서 다르다: {d['outside'][:8]}")
        versions = {k: receipt[k] for k in ("windowsBuild", "windowsVersion", "msixVersion")}
        identity = {"mode": "dev", "name": receipt["identity"]["name"]}
        report["arches"][arch].update(pack_verify(runner, exe, layout, receipt, mac_jar, mac_sha, identity, versions, arch, out))
    report["ok"] = True
    (out / "pack.json").write_text(json.dumps(report, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    print(json.dumps({k: {"bytes": v["bytes"], "fingerprint": v["unpack"]["fingerprint"],
                          "ciFingerprint": v["unpack"]["ciFingerprint"], "files": v["unpack"]["files"]}
                      for k, v in report["arches"].items()}, ensure_ascii=False))
    return 0


def key_sha8(key: str) -> str:
    return hashlib.sha256(key.encode("utf-8")).hexdigest()[:8] if key else ""


# ---- build ---------------------------------------------------------------------------------------

def cmd_build(a) -> int:
    ctx = preflight(a)
    out, prod, first = ctx["out"], ctx["prod"], ctx["first"]
    out.mkdir(parents=True, exist_ok=True)
    runner = Runner(out, prod["key"])
    report = {"schema": "aingcheck-windows-mac-repack/1", "ok": False, "dry": a.dry, "ciRun": a.ci_run or "",
              "gitSha": first["gitSha"], "buildTimeUtc": first["buildTimeUtc"], **ctx["versions"],
              "identity": {k: ctx["identity"][k] for k in ("name", "publisher", "mode")},
              "prodHost": rw.prod_host_for_receipt(prod["host"]), "prodKeySha8": key_sha8(prod["key"]),
              "makemsix": {k: ctx["makemsix"][k] for k in ("commit", "sha256")}, "arches": {}}
    try:
        layouts = {arch: extract_layout(ctx["ci"][arch], out / arch / "layout", arch) for arch in ctx["arches"]}
        # Gradle — 운영 값은 환경 변수로만(★3), 봉인 아래 --offline.
        started = time.time()
        rc = runner.run(gradle_argv(a, first), env=gradle_env(prod), cwd=MP, stdout=out / "gradle.log")
        if prod["key"].encode() in (out / "gradle.log").read_bytes():
            (out / "gradle.log").write_text("(키가 실려 지웠다)\n", encoding="utf-8")
            raise Fail("Gradle 로그에 anon 키가 실렸다")
        if rc != 0:
            raise Fail(f"Gradle 실패 rc={rc} — gradle.log")
        mac_jar = rw.find_app_jar(MP / "desktopApp" / "build" / "libs")
        mac_sha = rw.sha256_file(mac_jar)
        report["macJar"] = {"sha256": mac_sha, "fresh": mac_jar.stat().st_mtime >= started - 1}
        for arch in ctx["arches"]:
            r = ctx["ci"][arch]["receipt"]
            layout = layouts[arch]
            d = judge_jar(layout / r["appJar"]["name"], mac_jar, prod)
            report["arches"][arch] = {"jarDiff": {k: d[k] for k in ("ok", "changed", "outside", "prodOnly", "prodValues")}}
            if not d["ok"]:
                raise Fail(f"{arch}: 재빌드 jar 가 generated/ProdConfig 계열만 바뀐 것이 아니다 — outside={d['outside'][:8]} "
                           f"prodOnly={d['prodOnly']} prodValues={d['prodValues']}")
            report["arches"][arch].update(pack_verify(runner, ctx["makemsix"]["path"], layout, r, mac_jar, mac_sha,
                                                      ctx["identity"], ctx["versions"], arch, out))
        report["ok"] = True
    except Fail as e:
        report["error"] = str(e)
        raise
    finally:
        cmdlines = (out / "cmdlines.jsonl").read_text(encoding="utf-8") if (out / "cmdlines.jsonl").is_file() else ""
        report["cmdlinesKeyFree"] = prod["key"] not in cmdlines
        text = json.dumps(report, ensure_ascii=False, indent=1) + "\n"
        if prod["key"] in text or (not prod["host"].endswith(".invalid") and prod["host"] in text):
            text = json.dumps({"ok": False, "error": "보고서에 운영 값이 실려 쓰지 않았다"}) + "\n"
            report["ok"] = False
        (out / "repack.json").write_text(text, encoding="utf-8")
    if not report["cmdlinesKeyFree"]:
        raise Fail("cmdlines.jsonl 에 anon 키")
    if not a.dry:
        append_ledger(report)
    print(json.dumps({"ok": True, "dry": a.dry, "out": str(out), "arches": {
        k: {"msix": v["msix"], "fingerprint": v["unpack"]["fingerprint"]} for k, v in report["arches"].items()}},
        ensure_ascii=False))
    return 0


LEDGER_COLUMNS = ("windowsBuild", "windowsVersion", "msixVersion", "buildTimeUtc", "gitSha", "ciRun", "identity",
                  "prodHost", "prodKeySha8", "appJarSha256", "x64MsixSha256", "arm64MsixSha256", "recordedUtc")


def append_ledger(report: dict) -> None:
    text = LEDGER.read_text(encoding="utf-8") if LEDGER.is_file() else ""
    if not rw.ledger_next_ok(report["windowsBuild"], text):  # 쓰기 직전에 한 번 더(★2)
        raise Refuse("장부가 그 사이 올라갔다")
    row = [str(report["windowsBuild"]), report["windowsVersion"], report["msixVersion"], report["buildTimeUtc"],
           report["gitSha"], report["ciRun"], report["identity"]["name"], report["prodHost"], report["prodKeySha8"],
           report["macJar"]["sha256"]] + [report["arches"].get(x, {}).get("sha256", "-") for x in rw.ARCHES] + \
        [time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())]
    if any("\t" in c or "\n" in c for c in row):
        raise Fail("장부 칸에 탭·줄바꿈")
    if text and not text.endswith("\n"):
        text += "\n"
    LEDGER.write_text(text + "\t".join(row) + "\n", encoding="utf-8")


# ---- jar-diff · publish-sql ------------------------------------------------------------------------

def cmd_jar_diff(a) -> int:
    d = rw.jar_diff(a.ci_jar, a.mac_jar)
    d["prodOnly"] = bool(d["changed"]) and all(n.startswith(PROD_CONFIG_PREFIX) for n in d["changed"])
    print(json.dumps(d, ensure_ascii=False))
    if a.expect == "same":
        return 0 if not d["changed"] else 1
    return 0 if d["ok"] and d["prodOnly"] else 1


def ledger_rows() -> list[dict]:
    rows = []
    text = LEDGER.read_text(encoding="utf-8") if LEDGER.is_file() else ""
    for line in text.splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        cells = line.split("\t")
        if cells[0].strip().isdigit():
            rows.append(dict(zip(LEDGER_COLUMNS, cells)))
    return rows


def cmd_publish_sql(a) -> int:
    """client_publish_release_v2('windows', …) 한 줄을 찍기만 한다(★6 — 서버 비밀 키 전용 함수, 실행은 조정자가 사용자와)."""
    rows = [r for r in ledger_rows() if int(r["windowsBuild"]) == a.build]
    if len(rows) != 1:
        raise Refuse(f"장부에 windowsBuild {a.build} 줄이 하나가 아니다({len(rows)})")
    if not (1 <= a.min_build <= a.build <= 65535):
        raise Refuse(f"min_build {a.min_build} 는 1..{a.build}(이번 판) 이어야 한다")
    notes = (a.notes or "").strip()
    if len(notes) > 1000:
        raise Refuse("notes 는 1000자 이하")
    q = lambda s: "null" if not s else "'" + s.replace("'", "''") + "'"  # noqa: E731
    print(f"select public.client_publish_release_v2('windows', {a.min_build}, {a.build}, {q(notes)}, "
          f"{q(rows[0]['windowsVersion'])}, null);")
    return 0


def main(argv: list[str]) -> int:
    import argparse
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8", errors="backslashreplace")
        except (AttributeError, ValueError):
            pass
    p = argparse.ArgumentParser(prog="repack.sh")
    sub = p.add_subparsers(dest="cmd", required=True)
    b = sub.add_parser("build")
    b.add_argument("--ci", required=True, help="gh run download 받은 폴더(레이아웃 zip·영수증)")
    b.add_argument("--prod-config", required=True)
    b.add_argument("--out", required=True)
    b.add_argument("--identity", choices=("dev", "store"), default="store")
    b.add_argument("--arch", default="x64,arm64")
    b.add_argument("--dry", action="store_true", help="리허설 — 장부에 쓰지 않는다")
    b.add_argument("--ci-run", default="")
    b.add_argument("--gradle-project-cache", default="")
    b.add_argument("--makemsix", default="")
    j = sub.add_parser("jar-diff")
    j.add_argument("--ci-jar", required=True)
    j.add_argument("--mac-jar", required=True)
    j.add_argument("--expect", choices=("prod-only", "same"), default="prod-only")
    k = sub.add_parser("pack")
    k.add_argument("--ci", required=True)
    k.add_argument("--jar", required=True)
    k.add_argument("--out", required=True)
    k.add_argument("--arch", default="x64,arm64")
    k.add_argument("--makemsix", default="")
    s = sub.add_parser("publish-sql")
    s.add_argument("--build", type=int, required=True)
    s.add_argument("--min-build", type=int, required=True)
    s.add_argument("--notes", default="")
    try:
        a = p.parse_args(argv)
    except SystemExit as e:
        return 2 if e.code else 0
    try:
        return {"build": cmd_build, "pack": cmd_pack, "jar-diff": cmd_jar_diff, "publish-sql": cmd_publish_sql}[a.cmd](a)
    except Refuse as e:
        print(f"repack: 거부 — {e}", file=sys.stderr)
        return 2
    except (Fail, ValueError, KeyError, OSError, zipfile.BadZipFile, subprocess.CalledProcessError) as e:
        print(f"repack: 실패 — {type(e).__name__}: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
