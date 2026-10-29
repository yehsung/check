#!/usr/bin/env python3
"""아잉체크 Windows 포장 규칙의 정본(W6-b1, package.md §4-3). python3 -I 로 부른다(표준 라이브러리만).

release-windows.ps1(CI 러너·VM)과 W6-b2(맥 다시 싸기)가 같은 판정을 이 모듈 하나에서 가져간다 — 두 벌 금지.
맥 출시 규약을 옮긴 번호(★, package.md §2):
  ★1 종료 코드를 믿지 않는다 — 산출물 안 값(설치된 jar sha256 · selfcheck 의 build·buildTime·gitSha)으로 판정한다.
  ★2 Windows build 는 맥과 다른 정수 축. MSIX Version = windowsVersion + ".0"(Store 는 넷째 칸 0).
  ★3 값은 argv 로 — 셸 보간 금지. anon 키는 argv·로그·저장소·Actions 어디에도 싣지 않는다.
  ★4 유효 서명만으로는 부족하다 — 설치된 Publisher·서명 지문이 이번 실행의 인증서와 같아야 한다.
  ★5 운영 host 는 영수증·장부에 쓰지 않는다(.invalid 만 글자 그대로, 그 밖은 해시 8자리).
  ★6 Windows 는 profiles.app_build 를 PATCH 하지 않는다 — 이 모듈은 네트워크를 쓰지 않는다.
"""
from __future__ import annotations

import hashlib
import json
import re
import struct
import sys
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path
from xml.sax.saxutils import escape

PACKAGING = Path(__file__).resolve().parent
MP = PACKAGING.parent.parent
REPO = MP.parent

SCHEMA = "aingcheck-windows-receipt/1"
INSTALL_SCHEMA = "aingcheck-windows-install-check/1"
APP_ID = "AingCheck"
ALIAS = "aingcheck.exe"
TASK_ID = "AingCheck"
DATA_DIR_NAME = "aing-check"  # WindowsAppPaths.APP_DIR
GENERATED_PREFIX = "com/yehsung/aingcheck/desktop/generated/"
APP_JAR_MARKER = GENERATED_PREFIX + "BuildIdentity.class"
ARCHES = ("x64", "arm64")
STORE_PUBLISHER = re.compile(r"^CN=[0-9A-F-]{36}$")
IDENTITY_NAME = re.compile(r"^[A-Za-z0-9.-]{3,50}$")
GIT_SHA = re.compile(r"^[0-9a-f]{40}$")
PLACEHOLDER = re.compile(r"__|PLACEHOLDER|TODO|\{\{")

# 매니페스트가 가리키는 로고와 작업 표시줄용 unplated 크기(이름 → 한 변 픽셀). 원본은 저장소 packaging/appicon/icon-1024.png(맥 아이콘).
ASSET_TABLE = {
    "StoreLogo.png": 50,
    "Square44x44Logo.png": 44,
    "Square150x150Logo.png": 150,
    **{f"Square44x44Logo.targetsize-{n}_altform-unplated.png": n for n in (16, 24, 32, 48, 256)},
}
ICO_SIZES = (16, 24, 32, 48, 256)


# ---- 버전(★2) -------------------------------------------------------------------------------------

def read_props(path: Path) -> dict:
    out = {}
    for raw in Path(path).read_text(encoding="utf-8-sig").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        key, sep, value = line.partition("=")
        if not sep:
            raise ValueError(f"{path}: '=' 없는 줄: {raw!r}")
        out[key.strip()] = value.strip()
    return out


def msix_version(windows_version: str) -> str:
    """MAJOR.MINOR.BUILD(≤255·≤255·≤65535) → MAJOR.MINOR.BUILD.0. 그 밖은 ValueError."""
    parts = str(windows_version).split(".")
    if len(parts) != 3 or not all(p.isdigit() and (p == "0" or not p.startswith("0")) for p in parts):
        raise ValueError(f"windowsVersion 은 MAJOR.MINOR.BUILD 숫자 셋이어야 한다: {windows_version!r}")
    major, minor, build = (int(p) for p in parts)
    if major > 255 or minor > 255 or build > 65535:
        raise ValueError(f"windowsVersion 칸 범위(≤255.≤255.≤65535) 밖: {windows_version!r}")
    return f"{major}.{minor}.{build}.0"


def read_versions(path: Path | None = None) -> dict:
    props = read_props(path or MP / "version.properties")
    build = int(props["windowsBuild"])
    version = props["windowsVersion"]
    msix = msix_version(version)
    if int(version.split(".")[2]) != build:
        raise ValueError(f"windowsVersion 셋째 칸({version})이 windowsBuild({build})와 다르다")
    return {"windowsBuild": build, "windowsVersion": version, "msixVersion": msix}


# ---- 신원·매니페스트 ------------------------------------------------------------------------------

def load_identity(mode: str, identity_dir: Path | None = None) -> dict:
    if mode not in ("dev", "store"):
        raise ValueError(f"Identity 는 dev|store: {mode!r}")
    props = read_props(Path(identity_dir or PACKAGING / "identity") / f"{mode}.properties")
    ident = {k: props.get(k, "") for k in ("name", "publisher", "publisherDisplayName", "displayName")}
    ident["mode"] = mode
    missing = [k for k in ("name", "publisher", "publisherDisplayName", "displayName") if not ident[k]]
    if missing:
        raise ValueError(f"{mode}.properties 에 값이 없다: {missing}")
    if mode == "store":
        held = [k for k, v in props.items() if PLACEHOLDER.search(v)]
        if held:
            raise ValueError(f"store 신원에 자리표시 값이 남았다(U7 전): {sorted(held)}")
        if not STORE_PUBLISHER.match(ident["publisher"]):
            raise ValueError("store Publisher 는 Partner Center 의 CN=<GUID 대문자> 여야 한다")
    if not IDENTITY_NAME.match(ident["name"]):
        raise ValueError(f"Identity Name 형식 밖: {ident['name']!r}")
    return ident


def render_manifest(tpl: str, identity: dict, version: str, arch: str) -> str:
    if arch not in ARCHES:
        raise ValueError(f"arch 는 x64|arm64: {arch!r}")
    msix_version(".".join(version.split(".")[:3]))  # 칸 범위
    if not re.fullmatch(r"\d+\.\d+\.\d+\.0", version):
        raise ValueError(f"MSIX Version 넷째 칸은 0: {version!r}")
    values = {
        "NAME": identity["name"],
        "PUBLISHER": identity["publisher"],
        "PUBLISHER_DISPLAY_NAME": identity["publisherDisplayName"],
        "DISPLAY_NAME": identity["displayName"],
        "VERSION": version,
        "ARCH": arch,
    }
    out = tpl
    for key, value in values.items():
        out = out.replace("{{" + key + "}}", escape(value, {'"': "&quot;"}))
    left = re.findall(r"\{\{[^}]*\}\}|\{\{", out)
    if left:
        raise ValueError(f"매니페스트에 채우지 않은 자리가 남았다: {sorted(set(left))}")
    ET.fromstring(out.encode("utf-8"))  # 잘 짜인 XML
    return out


# ---- 자산(PNG·ICO) ---------------------------------------------------------------------------------

def png_size(data: bytes) -> tuple[int, int]:
    if data[:8] != b"\x89PNG\r\n\x1a\n" or data[12:16] != b"IHDR":
        raise ValueError("PNG 가 아니다")
    return struct.unpack(">II", data[16:24])


def ico_sizes(data: bytes) -> list[int]:
    reserved, kind, count = struct.unpack("<HHH", data[:6])
    if reserved != 0 or kind != 1:
        raise ValueError("ICO 가 아니다")
    sizes = []
    for i in range(count):
        w, h = data[6 + 16 * i], data[7 + 16 * i]
        size, offset = struct.unpack("<II", data[6 + 16 * i + 8: 6 + 16 * i + 16])
        w, h = (w or 256), (h or 256)
        blob = data[offset: offset + size]
        if blob[:8] == b"\x89PNG\r\n\x1a\n" and png_size(blob) != (w, h):
            raise ValueError(f"ICO 항목 {i} 의 PNG 크기가 디렉터리({w}×{h})와 다르다")
        if w != h:
            raise ValueError(f"ICO 항목 {i} 가 정사각형이 아니다")
        sizes.append(w)
    return sizes


def ico_from_pngs(pngs: list[bytes]) -> bytes:
    """PNG 항목 ICO(Vista 이상). 자산을 다시 만들 때만 쓴다."""
    head = struct.pack("<HHH", 0, 1, len(pngs))
    offset = 6 + 16 * len(pngs)
    entries, blobs = b"", b""
    for blob in pngs:
        w, h = png_size(blob)
        entries += struct.pack("<BBBBHHII", w % 256, h % 256, 0, 0, 1, 32, len(blob), offset)
        blobs += blob
        offset += len(blob)
    return head + entries + blobs


def asset_violations(packaging: Path = PACKAGING) -> list[str]:
    bad = []
    assets = packaging / "assets"
    for name, side in ASSET_TABLE.items():
        path = assets / name
        if not path.is_file():
            bad.append(f"없음: assets/{name}")
            continue
        size = png_size(path.read_bytes())
        if size != (side, side):
            bad.append(f"assets/{name}: {size[0]}×{size[1]} ≠ {side}×{side}")
    extra = sorted(p.name for p in assets.glob("*") if p.name not in ASSET_TABLE)
    if extra:
        bad.append(f"표에 없는 자산: {extra}")
    try:
        sizes = ico_sizes((packaging / "AingCheck.ico").read_bytes())
        if sorted(sizes) != sorted(ICO_SIZES):
            bad.append(f"AingCheck.ico 크기 {sizes} ≠ {list(ICO_SIZES)}")
    except (OSError, ValueError, struct.error) as e:
        bad.append(f"AingCheck.ico: {e}")
    return bad


def make_assets(src: Path, packaging: Path = PACKAGING) -> None:  # pragma: no cover — 맥에서 자산을 다시 만들 때만(sips)
    import subprocess
    import tempfile
    out = packaging / "assets"
    out.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        def resized(side: int) -> bytes:
            dst = Path(tmp) / f"{side}.png"
            subprocess.run(["/usr/bin/sips", "-z", str(side), str(side), str(src), "--out", str(dst)],
                           check=True, stdout=subprocess.DEVNULL)
            return dst.read_bytes()
        for name, side in ASSET_TABLE.items():
            (out / name).write_bytes(resized(side))
        (packaging / "AingCheck.ico").write_bytes(ico_from_pngs([resized(s) for s in ICO_SIZES]))


# ---- 원천 대조(Executable · 워크플로) ---------------------------------------------------------------

def strip_kotlin_comments(src: str) -> str:
    out, i, n = [], 0, len(src)
    while i < n:
        if src.startswith("//", i):
            j = src.find("\n", i)
            i = n if j < 0 else j
        elif src.startswith("/*", i):
            j = src.find("*/", i + 2)
            i = n if j < 0 else j + 2
        elif src[i] == '"':
            j = i + 1
            while j < n and src[j] != '"':
                j += 2 if src[j] == "\\" else 1
            out.append(src[i: j + 1])
            i = j + 1
        else:
            out.append(src[i])
            i += 1
    return "".join(out)


def compose_package_name(kts: str) -> str:
    """build-logic 의 nativeDistributions packageName(주석 걷고). 하나가 아니면 ValueError."""
    names = re.findall(r'\bpackageName\s*=\s*"([^"$]+)"', strip_kotlin_comments(kts))
    if len(names) != 1:
        raise ValueError(f"packageName = \"…\" 이 하나가 아니다: {names}")
    return names[0]


def manifest_facts(manifest: str) -> dict:
    root = ET.fromstring(manifest.encode("utf-8"))
    attrs = lambda local, attr: [el.get(attr) for el in root.iter() if el.tag.split("}")[-1] == local]
    return {
        "executables": sorted({v for el in root.iter() for k, v in el.attrib.items() if k == "Executable"}),
        "applicationIds": attrs("Application", "Id"),
        "aliases": attrs("ExecutionAlias", "Alias"),
        "startupTasks": [(t, e) for t, e in zip(attrs("StartupTask", "TaskId"), attrs("StartupTask", "Enabled"))],
        "backgroundColors": attrs("VisualElements", "BackgroundColor"),
        "logos": sorted({v for el in root.iter() for k, v in el.attrib.items() if k.endswith("Logo")}
                        | {el.text.strip() for el in root.iter() if el.tag.split("}")[-1] == "Logo" and el.text}),
    }


def strip_yaml_comments(text: str) -> str:
    lines = []
    for line in text.splitlines():
        quote, cut = None, len(line)
        for i, ch in enumerate(line):
            if quote:
                if ch == quote:
                    quote = None
            elif ch in "'\"":
                quote = ch
            elif ch == "#" and (i == 0 or line[i - 1] in " \t"):
                cut = i
                break
        lines.append(line[:cut].rstrip())
    return "\n".join(lines)


def workflow_violations(text: str) -> list[str]:
    body = strip_yaml_comments(text)
    bad = []
    if "secrets." in body or re.search(r"\bsecrets\s*\[", body):
        bad.append("secrets. 참조가 있다(키 없이 .invalid 로만 싼다)")
    m = re.search(r"(?m)^permissions:[ \t]*\n((?:[ \t]+\S.*\n?)+)", body)
    perms = [l.strip() for l in m.group(1).splitlines() if l.strip()] if m else []
    if perms != ["contents: read"]:
        bad.append(f"최상위 permissions 가 contents: read 하나가 아니다: {perms}")
    if re.search(r"(?m)^[ \t]+permissions:", body):
        bad.append("잡 단위 permissions 를 따로 두지 않는다")
    return bad


# ---- WACK ----------------------------------------------------------------------------------------

def wack_verdict(report_xml: str | None, mode: str, available: bool) -> dict:
    """mode require|auto|skip. 선택(OPTIONAL) 시험 FAIL 은 기록만 하고(package.md §5) 필수 FAIL 이 있으면 빨강."""
    out = {"available": bool(available), "mode": mode, "overall": None, "failed": [], "optionalFailed": [], "testCount": 0}
    if mode == "skip":
        out["ok"] = True
        return out
    if not available:
        out["ok"] = mode != "require"
        return out
    if not report_xml:
        out["overall"] = "NO_REPORT"
        out["ok"] = False
        return out
    root = ET.fromstring(report_xml.encode("utf-8") if isinstance(report_xml, str) else report_xml)
    out["overall"] = root.get("OVERALL_RESULT")
    for test in root.iter("TEST"):
        out["testCount"] += 1
        result = (test.findtext("RESULT") or "").strip().upper()
        if result == "FAIL":
            optional = (test.get("OPTIONAL") or "").strip().upper() == "TRUE"
            (out["optionalFailed"] if optional else out["failed"]).append(test.get("NAME"))
    out["ok"] = out["testCount"] > 0 and not out["failed"] and (out["overall"] == "PASS" or bool(out["optionalFailed"]))
    return out


# ---- 영수증(★1·★5) -------------------------------------------------------------------------------

def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def find_app_jar(app_dir: Path) -> Path:
    hits = []
    for jar in sorted(Path(app_dir).glob("*.jar")):
        with zipfile.ZipFile(jar) as z:
            if APP_JAR_MARKER in z.namelist():
                hits.append(jar)
    if len(hits) != 1:
        raise ValueError(f"{APP_JAR_MARKER} 를 가진 jar 가 하나가 아니다: {[p.name for p in hits]}")
    return hits[0]


def prod_host_for_receipt(host: str) -> str:
    host = (host or "").strip().lower()
    if host.endswith(".invalid"):
        return host
    return "sha8:" + hashlib.sha256(host.encode("utf-8")).hexdigest()[:8]


def build_receipt(layout: Path, selfcheck: dict, identity: dict, arch: str, git_sha: str, build_time: str,
                  versions: dict, wack: dict) -> dict:
    """앱 이미지 selfcheck 가 이번 빌드(gitSha·buildTime·version.properties)와 같을 때만 영수증을 만든다(★1)."""
    if not GIT_SHA.match(git_sha or ""):
        raise ValueError(f"gitSha 는 40자 소문자 hex: {git_sha!r}")
    if not build_time or build_time == "dev":
        raise ValueError("buildTime 이 비었거나 기본값(dev)이다")
    want = {"gitSha": git_sha, "buildTime": build_time, "build": str(versions["windowsBuild"]),
            "version": versions["windowsVersion"], "platform": "windows"}
    got = {k: (str(selfcheck.get(k)) if selfcheck.get(k) is not None else None) for k in want}
    if got != want:
        raise ValueError(f"앱 이미지 selfcheck 가 이번 빌드와 다르다: want={want} got={got}")
    host = prod_host_for_receipt(selfcheck.get("prodHost", ""))
    if identity["mode"] == "dev" and not host.endswith(".invalid"):
        raise ValueError("dev 신원 패키지에 운영 구성이 들어 있다(CI 는 .invalid 로만 싼다)")
    layout = Path(layout)
    jar = find_app_jar(layout / "app")
    files = [{"path": p.relative_to(layout).as_posix(), "sha256": sha256_file(p), "bytes": p.stat().st_size}
             for p in sorted(layout.rglob("*")) if p.is_file()]
    return {
        "schema": SCHEMA,
        "gitSha": git_sha,
        "buildTimeUtc": build_time,
        "windowsBuild": versions["windowsBuild"],
        "windowsVersion": versions["windowsVersion"],
        "msixVersion": versions["msixVersion"],
        "arch": arch,
        "identity": {"name": identity["name"], "publisher": identity["publisher"], "mode": identity["mode"]},
        "appJar": {"name": jar.relative_to(layout).as_posix(), "sha256": sha256_file(jar)},
        "files": files,
        "prodHost": host,
        "prodKeySha8": str(selfcheck.get("prodKeySha8", "")),
        "wack": {k: wack.get(k) for k in ("available", "overall", "failed", "optionalFailed", "ok")},
    }


def _norm_path(p: str) -> str:
    return (p or "").replace("/", "\\").rstrip("\\").lower()


def check_install(receipt: dict, selfcheck: dict | None, facts: dict) -> dict:
    """설치된 패키지가 '이번 빌드'인가(★1·★4). ok 는 모든 검사의 곱 — 종료 코드는 여기서 파생한다."""
    checks = []

    def check(cid: str, expected, actual, ok=None):
        passed = (expected == actual) if ok is None else bool(ok)
        checks.append({"id": cid, "ok": passed, "expected": expected, "actual": actual})

    if receipt.get("schema") != SCHEMA:
        check("receipt.schema", SCHEMA, receipt.get("schema"))
    sc = selfcheck or {}
    check("selfcheck.present", True, bool(selfcheck))
    check("selfcheck.exit", 0, facts.get("selfcheckExit"))
    check("platform", "windows", sc.get("platform"))
    check("build", str(receipt.get("windowsBuild")), str(sc.get("build")))
    check("version", receipt.get("windowsVersion"), sc.get("version"))
    check("buildTime", receipt.get("buildTimeUtc"), sc.get("buildTime"))
    check("gitSha", receipt.get("gitSha"), sc.get("gitSha"))
    check("prodHost", receipt.get("prodHost"), prod_host_for_receipt(sc.get("prodHost", "")))
    check("prodKeySha8", receipt.get("prodKeySha8"), str(sc.get("prodKeySha8", "")))
    name = (receipt.get("identity") or {}).get("name", "")
    pfn = facts.get("packageFamilyName") or ""
    check("pfn.matchesInstalled", pfn, sc.get("packageFamilyName"), ok=bool(pfn) and sc.get("packageFamilyName") == pfn)
    check("pfn.identityName", name + "_…", pfn, ok=bool(name) and pfn.startswith(name + "_"))
    want_data = "\\".join([facts.get("localAppData", ""), "Packages", pfn, "LocalCache", "Local", DATA_DIR_NAME])
    check("dataDir", want_data, sc.get("dataDir"),
          ok=bool(pfn and facts.get("localAppData")) and _norm_path(sc.get("dataDir")) == _norm_path(want_data))
    jar = receipt.get("appJar") or {}
    check("appJar.sha256", jar.get("sha256"), facts.get("installedJarSha256"),
          ok=bool(jar.get("sha256")) and jar.get("sha256") == facts.get("installedJarSha256"))
    publisher = (receipt.get("identity") or {}).get("publisher")
    check("publisher.installed", publisher, facts.get("installedPublisher"))
    if facts.get("mode") != "register":
        exp = (facts.get("expectedThumbprint") or "").upper()
        got = (facts.get("signerThumbprint") or "").upper()
        check("signer.thumbprint", exp, got, ok=bool(exp) and exp == got)
        check("signer.subject", publisher, facts.get("signerSubject"))
    check("removed", 0, facts.get("remainingAfterRemove"))
    return {"schema": INSTALL_SCHEMA, "ok": all(c["ok"] for c in checks), "mode": facts.get("mode"),
            "failed": [c["id"] for c in checks if not c["ok"]], "checks": checks}


def bundle_plan(receipts: list[dict]) -> dict:
    if not receipts:
        raise ValueError("영수증이 없다")
    keys = ("msixVersion", "gitSha", "buildTimeUtc")
    first = receipts[0]
    for r in receipts:
        if r.get("schema") != SCHEMA:
            raise ValueError(f"영수증 schema 가 다르다: {r.get('schema')!r}")
        if r.get("identity") != first.get("identity") or any(r.get(k) != first.get(k) for k in keys):
            raise ValueError("묶을 패키지의 신원·버전·빌드가 서로 다르다")
    arches = sorted(r["arch"] for r in receipts)
    if len(set(arches)) != len(arches):
        raise ValueError(f"같은 아키텍처가 둘: {arches}")
    return {"identity": first["identity"], "msixVersion": first["msixVersion"], "arches": arches,
            "bundleName": f"AingCheck_{first['windowsVersion']}.msixbundle"}


# ---- W6-b2 가 쓰는 규칙 ---------------------------------------------------------------------------

def jar_diff(ci_jar, mac_jar, allow=(GENERATED_PREFIX,)) -> dict:
    """두 jar 의 항목 내용 차이(타임스탬프 무시). 허용 접두 밖 차이가 하나라도 있으면 ok=false."""
    def entries(path):
        with zipfile.ZipFile(path) as z:
            return {i.filename: z.read(i.filename) for i in z.infolist() if not i.is_dir()}
    a, b = entries(ci_jar), entries(mac_jar)
    changed = sorted(n for n in set(a) | set(b) if a.get(n) != b.get(n))
    outside = [n for n in changed if not n.startswith(tuple(allow))]
    return {"ok": not outside, "changed": changed, "outside": outside}


def ledger_next_ok(build: int, tsv: str) -> bool:
    """장부(TSV, '#' 주석, 첫 칸 또는 'windowsBuild' 머리 칸이 build)의 최댓값보다 커야 한다."""
    rows = [l.split("\t") for l in tsv.splitlines() if l.strip() and not l.lstrip().startswith("#")]
    col = 0
    if rows and not rows[0][0].strip().isdigit():
        header = [c.strip() for c in rows.pop(0)]
        col = header.index("windowsBuild") if "windowsBuild" in header else 0
    builds = [int(r[col]) for r in rows if len(r) > col and r[col].strip().isdigit()]
    return int(build) > max(builds, default=0)


# ---- CLI(release-windows.ps1 이 argv 로 부른다 — ★3) ---------------------------------------------

def _load_json(path: str):
    return json.loads(Path(path).read_text(encoding="utf-8-sig")) if path and Path(path).is_file() else None


def _write_json(path: str, obj) -> None:
    Path(path).write_text(json.dumps(obj, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main(argv: list[str]) -> int:
    import argparse
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8", errors="backslashreplace")
        except (AttributeError, ValueError):
            pass
    p = argparse.ArgumentParser(prog="release_win.py")
    sub = p.add_subparsers(dest="cmd", required=True)
    m = sub.add_parser("manifest")
    m.add_argument("--identity", required=True)
    m.add_argument("--arch", required=True)
    m.add_argument("--out", required=True)
    r = sub.add_parser("receipt")
    for a in ("--layout", "--selfcheck", "--identity", "--arch", "--git-sha", "--build-time", "--wack", "--out"):
        r.add_argument(a, required=True)
    w = sub.add_parser("wack")
    w.add_argument("--mode", required=True, choices=("require", "auto", "skip"))
    w.add_argument("--available", required=True, choices=("true", "false"))
    w.add_argument("--report", default="")
    w.add_argument("--out", required=True)
    c = sub.add_parser("check-install")
    for a in ("--expect", "--selfcheck", "--facts", "--out"):
        c.add_argument(a, required=True)
    b = sub.add_parser("bundle-plan")
    b.add_argument("--out", required=True)
    b.add_argument("receipts", nargs="+")
    t = sub.add_parser("tamper-receipt", help="러너 음성 대조용: gitSha 를 바꾼 사본")
    t.add_argument("--in", dest="src", required=True)
    t.add_argument("--out", required=True)
    args = p.parse_args(argv)
    try:
        if args.cmd == "manifest":
            ident = load_identity(args.identity)
            versions = read_versions()
            tpl = (PACKAGING / "AppxManifest.template.xml").read_text(encoding="utf-8")
            Path(args.out).write_text(render_manifest(tpl, ident, versions["msixVersion"], args.arch), encoding="utf-8")
            print(json.dumps({"ok": True, **versions, "identity": {k: ident[k] for k in ("name", "publisher", "mode")}}))
        elif args.cmd == "receipt":
            receipt = build_receipt(Path(args.layout), _load_json(args.selfcheck) or {}, load_identity(args.identity),
                                    args.arch, args.git_sha, args.build_time, read_versions(), _load_json(args.wack) or {})
            _write_json(args.out, receipt)
            print(json.dumps({"ok": True, "appJar": receipt["appJar"], "files": len(receipt["files"])}))
        elif args.cmd == "wack":
            report = Path(args.report).read_text(encoding="utf-8-sig") if args.report and Path(args.report).is_file() else None
            verdict = wack_verdict(report, args.mode, args.available == "true")
            _write_json(args.out, verdict)
            print(json.dumps(verdict))
            return 0 if verdict["ok"] else 1
        elif args.cmd == "check-install":
            result = check_install(_load_json(args.expect) or {}, _load_json(args.selfcheck), _load_json(args.facts) or {})
            _write_json(args.out, result)
            print(json.dumps({"ok": result["ok"], "failed": result["failed"]}))
            return 0 if result["ok"] else 1
        elif args.cmd == "bundle-plan":
            plan = bundle_plan([_load_json(x) for x in args.receipts])
            _write_json(args.out, plan)
            print(json.dumps(plan))
        elif args.cmd == "tamper-receipt":
            receipt = _load_json(args.src)
            receipt["gitSha"] = "0" * 40 if receipt.get("gitSha") != "0" * 40 else "f" * 40
            _write_json(args.out, receipt)
        return 0
    except (ValueError, KeyError, OSError) as e:
        print(json.dumps({"ok": False, "error": f"{type(e).__name__}: {e}"}, ensure_ascii=False))
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
