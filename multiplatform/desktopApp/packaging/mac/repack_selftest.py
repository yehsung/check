#!/usr/bin/env python3
"""repack.sh self-test(W6-b2 · package.md §5) — 가짜 zip 산출물·가짜 Gradle·가짜 makemsix·임시 git 저장소로 거부·판정·장부·명령줄을 잰다.

망·진짜 Gradle·makemsix·사용자 비밀 없음. 운영 값은 실행마다 만든 가짜(.invalid · .example host, 무작위 키).
시험 이름의 ★ 번호는 repack.py 머리(맥 출시 규약 package.md §2)와 같다.
"""
from __future__ import annotations

import sys

sys.dont_write_bytecode = True  # -I 는 PYTHONDONTWRITEBYTECODE 를 무시한다 — __pycache__ 를 저장소에 흘리지 않는다
import hashlib  # noqa: E402
import json  # noqa: E402
import os  # noqa: E402
import secrets  # noqa: E402
import shutil  # noqa: E402
import subprocess  # noqa: E402
import tempfile  # noqa: E402
import unittest  # noqa: E402
import zipfile  # noqa: E402
from pathlib import Path  # noqa: E402

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
import release_win as rw  # noqa: E402

REPACK_SH = HERE / "repack.sh"
BUILD_TIME = "2026-10-29T01:02:03Z"
GEN = rw.GENERATED_PREFIX
MAIN_CLASS = "com/yehsung/aingcheck/desktop/MainKt.class"
JAR_NAME = "app/desktopApp-0123456789abcdef.jar"

STUB_GRADLE = r'''
import hashlib, json, os, sys, zipfile
from pathlib import Path
mp = Path(sys.argv[0]).resolve().parent
mode = os.environ.get("SELFTEST_GRADLE_MODE", "ok")
url = os.environ.get("ORG_GRADLE_PROJECT_aingcheck.prod.supabaseUrl", "")
key = os.environ.get("ORG_GRADLE_PROJECT_aingcheck.prod.supabaseAnonKey", "")
with open(mp / "gradle-record.jsonl", "a") as f:
    f.write(json.dumps({"argv": sys.argv[1:], "envUrl": url, "envKeySha": hashlib.sha256(key.encode()).hexdigest()}) + "\n")
if mode == "fail":
    print("BUILD FAILED"); sys.exit(1)
if mode == "leak":
    print("property aingcheck.prod.supabaseAnonKey=" + key)
src = zipfile.ZipFile(os.environ["SELFTEST_CI_JAR"])
out = mp / "desktopApp" / "build" / "libs" / "desktopApp.jar"
out.parent.mkdir(parents=True, exist_ok=True)
with zipfile.ZipFile(out, "w") as z:
    for n in src.namelist():
        data = src.read(n)
        if n.endswith("ProdConfig.class") and mode != "same":
            data = b"\xca\xfe\xba\xbe-prod-" + url.encode() + b"|" + key.encode()
        if n.endswith("DesktopFlags.class") and mode == "flags":
            data += b"-duels-true"
        if n.endswith("MainKt.class") and mode == "outside":
            data += b"-one-source-line-changed"
        z.writestr(n, data)
print("BUILD SUCCESSFUL")
'''

STUB_MAKEMSIX = r'''
import os, sys, zipfile
from pathlib import Path
mode = os.environ.get("SELFTEST_MAKEMSIX_MODE", "ok")
cmd, args = sys.argv[1], sys.argv[2:]
opt = {args[i]: args[i + 1] for i in range(0, len(args) - 1) if args[i] in ("-d", "-p")}
if cmd == "pack":
    if mode == "noout":
        sys.exit(0)
    root = Path(opt["-d"])
    with zipfile.ZipFile(opt["-p"], "w") as z:
        z.writestr("AppxBlockMap.xml", "<BlockMap/>")
        z.writestr("[Content_Types].xml", "<Types/>")
        for p in sorted(root.rglob("*")):
            rel = p.relative_to(root).as_posix()
            if p.is_file() and not (mode == "drop" and rel.startswith("runtime/")):
                z.write(p, rel)
elif cmd == "unpack":
    zipfile.ZipFile(opt["-p"]).extractall(opt["-d"])
'''


def sha(b: bytes) -> str:
    return hashlib.sha256(b).hexdigest()


def git(repo: Path, *args: str) -> str:
    return subprocess.run(["git", "-C", str(repo), "-c", "user.email=selftest@invalid", "-c", "user.name=selftest",
                           "-c", "commit.gpgsign=false", *args], check=True, capture_output=True, text=True).stdout


class World:
    """임시 git 저장소(가짜 multiplatform) + 가짜 CI 산출물 + 가짜 도구."""

    def __init__(self, tmp: Path, ledger_max: int = 5):
        self.tmp = tmp
        self.repo = tmp / "repo"
        self.mp = self.repo / "multiplatform"
        pk = self.mp / "desktopApp" / "packaging"
        (pk / "identity").mkdir(parents=True)
        (self.mp / "version.properties").write_text("windowsBuild=7\nwindowsVersion=1.0.7\n", encoding="utf-8")
        (self.mp / "gradlew").write_text('#!/bin/sh\nexec python3 -I "$(dirname "$0")/stub_gradle.py" "$@"\n', encoding="utf-8")
        (self.mp / "stub_gradle.py").write_text(STUB_GRADLE, encoding="utf-8")
        (self.mp / ".gitignore").write_text("build/\ngradle-record.jsonl\n", encoding="utf-8")
        shutil.copyfile(rw.PACKAGING / "AppxManifest.template.xml", pk / "AppxManifest.template.xml")
        shutil.copyfile(rw.PACKAGING / "identity" / "dev.properties", pk / "identity" / "dev.properties")
        (pk / "identity" / "store.properties").write_text(
            "name=Selftest.AingCheck\npublisher=CN=12345678-ABCD-4321-ABCD-1234567890AB\n"
            "publisherDisplayName=Selftest\ndisplayName=Selftest\n", encoding="utf-8")
        self.ledger = pk / "versions.tsv"
        self.ledger.write_text("# 자기 시험 장부\nwindowsBuild\twindowsVersion\n" + f"{ledger_max}\t1.0.{ledger_max}\n", encoding="utf-8")
        git(self.repo, "init", "-q")
        git(self.repo, "add", "-A")
        git(self.repo, "commit", "-q", "-m", "selftest")
        self.head = git(self.repo, "rev-parse", "HEAD").strip()
        # CI jar(아키텍처와 무관 — 같은 jar)
        self.ci_jar = tmp / "ci-desktopApp.jar"
        with zipfile.ZipFile(self.ci_jar, "w") as z:
            z.writestr("META-INF/MANIFEST.MF", "Manifest-Version: 1.0\n")
            z.writestr(GEN + "BuildIdentity.class", b"\xca\xfe\xba\xbe" + self.head.encode() + BUILD_TIME.encode())
            z.writestr(GEN + "ProdConfig.class", b"\xca\xfe\xba\xbe-prod-https://aingcheck.invalid|")
            z.writestr(GEN + "DesktopFlags.class", b"\xca\xfe\xba\xbe-flags-false")
            z.writestr(MAIN_CLASS, b"\xca\xfe\xba\xbe-main")
        self.ci = tmp / "ci"
        for arch in rw.ARCHES:
            self.make_ci(arch)
        tools = tmp / "tools"
        tools.mkdir()
        (tools / "stub_makemsix.py").write_text(STUB_MAKEMSIX, encoding="utf-8")
        self.makemsix = tools / "makemsix"
        self.makemsix.write_text(f'#!/bin/bash\nexec python3 -I "{tools / "stub_makemsix.py"}" "$@"\n', encoding="utf-8")
        self.makemsix.chmod(0o755)
        self.key = "selftest-anon-" + secrets.token_hex(12)
        self.prod_dry = self.props(url="https://selftest-prod.invalid")
        self.prod_store = self.props(url="https://selftest-prod.example", name="prod-store")
        self.runs = 0

    def make_ci(self, arch: str, tamper: bool = False) -> None:
        layout = self.tmp / f"layout-{arch}"
        files = {"AppxManifest.xml": b"<Package/>", "AingCheck.exe": b"MZ-" + arch.encode(), "resources.pri": b"pri",
                 "Assets/StoreLogo.png": b"png", "app/AingCheck.cfg": f"[Application]\napp.classpath=$APPDIR\\{JAR_NAME[4:]}\n".encode(),
                 JAR_NAME: self.ci_jar.read_bytes(), "runtime/bin/java.dll": b"java-" + arch.encode(),
                 "runtime/lib/modules": b"modules"}
        shutil.rmtree(layout, ignore_errors=True)
        for rel, data in files.items():
            (layout / rel).parent.mkdir(parents=True, exist_ok=True)
            (layout / rel).write_bytes(data)
        receipt = {"schema": rw.SCHEMA, "gitSha": self.head, "buildTimeUtc": BUILD_TIME, "windowsBuild": 7,
                   "windowsVersion": "1.0.7", "msixVersion": "1.0.7.0", "arch": arch,
                   "identity": {"name": "AingCheck.Dev", "publisher": "CN=AingCheck Dev Test", "mode": "dev"},
                   "appJar": {"name": JAR_NAME, "sha256": sha(files[JAR_NAME])},
                   "files": [{"path": p, "sha256": sha(d), "bytes": len(d)} for p, d in sorted(files.items())],
                   "prodHost": "aingcheck.invalid", "prodKeySha8": "", "wack": {}}
        if tamper:
            (layout / "runtime/lib/modules").write_bytes(b"tampered")
        d = self.ci / f"windows-{arch}"
        d.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(d / f"AingCheck_1.0.7_{arch}.layout.zip", "w") as z:
            for p in sorted(layout.rglob("*")):
                if p.is_file():
                    z.write(p, p.relative_to(layout).as_posix())
        (d / f"AingCheck_1.0.7_{arch}.receipt.json").write_text(json.dumps(receipt), encoding="utf-8")

    def props(self, url: str | None = None, key: str | None = "", name: str = "prod", extra: str = "") -> Path:
        p = self.tmp / f"{name}.properties"
        lines = []
        if url is not None:
            lines.append(f"aingcheck.prod.supabaseUrl={url}")
        if key is not None:
            lines.append(f"aingcheck.prod.supabaseAnonKey={key if key != '' else self.key}")
        p.write_text("\n".join(lines) + "\n" + extra, encoding="utf-8")
        return p

    def run(self, *args: str, gradle: str = "ok", makemsix: str = "ok", prod: Path | None = None,
            identity: str = "dev", dry: bool = True, out: Path | None = None) -> tuple[int, str, Path]:
        self.runs += 1
        out = out or self.tmp / f"out{self.runs}"
        argv = list(args) or ["build", "--ci", str(self.ci), "--prod-config", str(prod or self.prod_dry), "--out", str(out),
                              "--identity", identity, "--makemsix", str(self.makemsix), "--ci-run", "123"] + (["--dry"] if dry else [])
        env = {k: v for k, v in os.environ.items() if not k.startswith(("ORG_GRADLE_PROJECT_", "SELFTEST_", "AINGCHECK_"))}
        env.update({"AINGCHECK_REPACK_SELFTEST": "1", "AINGCHECK_REPACK_MP": str(self.mp), "AINGCHECK_REPACK_SEAL": "none",
                    "SELFTEST_CI_JAR": str(self.ci_jar), "SELFTEST_GRADLE_MODE": gradle, "SELFTEST_MAKEMSIX_MODE": makemsix})
        p = subprocess.run(["bash", str(REPACK_SH), *argv], env=env, capture_output=True, text=True)
        return p.returncode, p.stdout + p.stderr, out

    def gradle_records(self) -> list[dict]:
        f = self.mp / "gradle-record.jsonl"
        return [json.loads(x) for x in f.read_text().splitlines()] if f.is_file() else []


class RepackSelfTest(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory(prefix="aingcheck-repack-selftest-")
        self.w = World(Path(self._tmp.name))

    def tearDown(self):
        self._tmp.cleanup()

    def assertKeyFree(self, out: Path):
        for f in out.rglob("*"):
            if f.is_file() and f.suffix in (".jsonl", ".json", ".log"):
                self.assertNotIn(self.w.key, f.read_text(encoding="utf-8", errors="replace"), f.name)

    def test_01_dry_green_key_only_in_env_star3(self):
        rc, log, out = self.w.run()
        self.assertEqual(rc, 0, log)
        rep = json.loads((out / "repack.json").read_text())
        self.assertTrue(rep["ok"])
        self.assertEqual(rep["prodHost"], "selftest-prod.invalid")
        self.assertEqual(rep["prodKeySha8"], sha(self.w.key.encode())[:8])
        for arch in rw.ARCHES:
            self.assertEqual(rep["arches"][arch]["jarDiff"]["changed"], [GEN + "ProdConfig.class"])
            self.assertTrue(rep["arches"][arch]["unpack"]["ok"])
            self.assertTrue((out / f"AingCheck_1.0.7_{arch}.msix").is_file())
        # 자식 명령줄 기록에 키 0 · 키는 환경 변수로 도착(★3)
        cmdlines = (out / "cmdlines.jsonl").read_text()
        self.assertNotIn(self.w.key, cmdlines)
        self.assertEqual(len(cmdlines.splitlines()), 1 + 2 * len(rw.ARCHES))
        rec = self.w.gradle_records()
        self.assertEqual(len(rec), 1)
        self.assertEqual(rec[0]["envKeySha"], sha(self.w.key.encode()))
        self.assertNotIn(self.w.key, json.dumps(rec[0]["argv"]))
        for flag in ("--offline", "-Paingcheck.desktop.releaseAssembly=true", f"-Paingcheck.buildTime={BUILD_TIME}",
                     f"-Paingcheck.gitSha={self.w.head}", ":desktopApp:jar"):
            self.assertIn(flag, rec[0]["argv"])
        self.assertKeyFree(out)
        self.assertEqual(self.w.ledger.read_text().count("\n"), 3, "--dry 는 장부에 쓰지 않는다")

    def test_02_store_writes_ledger_once_star2_star5(self):
        rc, log, out = self.w.run(prod=self.w.prod_store, identity="store", dry=False)
        self.assertEqual(rc, 0, log)
        last = self.w.ledger.read_text().splitlines()[-1].split("\t")
        self.assertEqual(last[0], "7")
        self.assertEqual(last[7], "sha8:" + sha(b"selftest-prod.example")[:8])
        text = self.w.ledger.read_text()
        self.assertNotIn("selftest-prod.example", text)
        self.assertNotIn(self.w.key, text)
        self.assertKeyFree(out)
        manifest = (out / "x64" / "unpacked" / "AppxManifest.xml").read_text(encoding="utf-8")
        self.assertIn('Name="Selftest.AingCheck"', manifest)
        rc, log, _ = self.w.run(prod=self.w.prod_store, identity="store", dry=False)
        self.assertEqual(rc, 2, log)
        self.assertIn("장부", log)
        # publish-sql 은 장부 줄로 한 줄만 찍는다(★6)
        rc, log, _ = self.w.run("publish-sql", "--build", "7", "--min-build", "1", "--notes", "it's")
        self.assertEqual(rc, 0, log)
        self.assertEqual(log.strip(), "select public.client_publish_release_v2('windows', 1, 7, 'it''s', '1.0.7', null);")
        self.assertEqual(self.w.run("publish-sql", "--build", "7", "--min-build", "8")[0], 2)
        self.assertEqual(self.w.run("publish-sql", "--build", "6", "--min-build", "1")[0], 2)

    def test_03_build_not_above_ledger_max_refused_star2(self):
        self._tmp.cleanup()
        self._tmp = tempfile.TemporaryDirectory(prefix="aingcheck-repack-selftest-")
        self.w = World(Path(self._tmp.name), ledger_max=7)
        rc, log, _ = self.w.run()
        self.assertEqual(rc, 2, log)
        self.assertIn("장부", log)
        self.assertEqual(self.w.gradle_records(), [], "거부는 Gradle 전에")

    def test_04_gitsha_not_head_refused(self):
        (self.w.mp / "later.txt").write_text("x")
        git(self.w.repo, "add", "-A")
        git(self.w.repo, "commit", "-q", "-m", "later")
        rc, log, _ = self.w.run()
        self.assertEqual(rc, 2, log)
        self.assertIn("HEAD", log)

    def test_05_missing_prod_value_exit_2(self):
        cases = {"no-url": self.w.props(url=None, name="a"), "no-key": self.w.props(url="https://x.invalid", key=None, name="b"),
                 "empty-key": self.w.props(url="https://x.invalid", key="  ", name="c"),
                 "unknown": self.w.props(url="https://x.invalid", name="d", extra="aingcheck.windows.duels=true\n"),
                 "http": self.w.props(url="http://x.invalid", name="e"),
                 "secret": self.w.props(url="https://x.invalid", key="sb" + "_secret_abc", name="f"),
                 "missing-file": self.w.tmp / "nope.properties"}
        for name, prod in cases.items():
            rc, log, _ = self.w.run(prod=prod)
            self.assertEqual(rc, 2, f"{name}: {log}")
        self.assertEqual(self.w.gradle_records(), [])

    def test_06_jar_change_outside_allowlist_refused_star1(self):
        rc, log, out = self.w.run(gradle="outside")
        self.assertEqual(rc, 1, log)
        rep = json.loads((out / "repack.json").read_text())
        self.assertFalse(rep["ok"])
        self.assertIn(MAIN_CLASS, rep["arches"]["x64"]["jarDiff"]["outside"])
        self.assertFalse(list(out.glob("*.msix")))

    def test_07_prodconfig_unchanged_refused_star1(self):
        rc, log, _ = self.w.run(gradle="same")
        self.assertEqual(rc, 1, log)

    def test_08_key_in_gradle_log_fails_star3(self):
        rc, log, out = self.w.run(gradle="leak")
        self.assertEqual(rc, 1, log)
        self.assertKeyFree(out)

    def test_09_dirty_tree_outside_own_refused(self):
        own = self.w.mp / "desktopApp" / "packaging" / "mac"
        own.mkdir()
        (own / "note.txt").write_text("own")
        self.assertEqual(self.w.run()[0], 0, "packaging/mac 안은 더러워도 된다")
        src = self.w.mp / "desktopApp" / "src"
        src.mkdir()
        (src / "Main.kt").write_text("// 한 줄")
        rc, log, _ = self.w.run()
        self.assertEqual(rc, 2, log)
        self.assertIn("더럽다", log)

    def test_10_unpacked_differs_from_ci_layout_fails_star1(self):
        rc, log, out = self.w.run(makemsix="drop")
        self.assertEqual(rc, 1, log)
        self.assertIn("runtime", log)

    def test_11_makemsix_rc0_without_output_fails_star1(self):
        rc, log, _ = self.w.run(makemsix="noout")
        self.assertEqual(rc, 1, log)

    def test_12_ci_layout_zip_not_receipt_fails_star1(self):
        self.w.make_ci("arm64", tamper=True)
        rc, log, _ = self.w.run()
        self.assertEqual(rc, 1, log)
        self.assertIn("영수증", log)

    def test_13_identity_rules(self):
        self.assertEqual(self.w.run(identity="dev", dry=False)[0], 2, "dev 신원은 장부에 못 오른다")
        self.assertEqual(self.w.run(prod=self.w.prod_store, identity="dev")[0], 2, "dev 에 운영 host 금지")
        self.assertEqual(self.w.run(identity="store", dry=False)[0], 2, "장부 판에 .invalid host 금지")

    def test_14_gradle_failure_exit_1(self):
        self.assertEqual(self.w.run(gradle="fail")[0], 1)

    def test_15_generated_but_not_prodconfig_refused_w3_17(self):
        # W-3 #17: 깃발(DesktopFlags)·BuildIdentity 는 generated 패키지라 jar_diff 허용 목록 안이지만, 다시 싸기에서는 CI 와 같아야 한다.
        rc, log, out = self.w.run(gradle="flags")
        self.assertEqual(rc, 1, log)
        self.assertIn(GEN + "DesktopFlags.class", json.loads((out / "repack.json").read_text())["arches"]["x64"]["jarDiff"]["changed"])

    def test_16_pack_stage_only(self):
        rc, log, out = self.w.run("pack", "--ci", str(self.w.ci), "--jar", str(self.w.ci_jar), "--out", str(self.w.tmp / "p1"),
                                  "--makemsix", str(self.w.makemsix))
        self.assertEqual(rc, 0, log)
        rep = json.loads((self.w.tmp / "p1" / "pack.json").read_text())
        for arch in rw.ARCHES:
            self.assertEqual(rep["arches"][arch]["unpack"]["fingerprint"], rep["arches"][arch]["unpack"]["ciFingerprint"])
        bad = self.w.tmp / "bad.jar"
        with zipfile.ZipFile(self.w.ci_jar) as src, zipfile.ZipFile(bad, "w") as z:
            for n in src.namelist():
                z.writestr(n, src.read(n) + (b"-x" if n == MAIN_CLASS else b""))
        rc, log, _ = self.w.run("pack", "--ci", str(self.w.ci), "--jar", str(bad), "--out", str(self.w.tmp / "p2"),
                                "--makemsix", str(self.w.makemsix))
        self.assertEqual(rc, 1, log)
        rc, log, _ = self.w.run("pack", "--ci", str(self.w.ci), "--jar", str(self.w.ci_jar), "--out", str(self.w.tmp / "p3"),
                                "--makemsix", str(self.w.makemsix), makemsix="drop")
        self.assertEqual(rc, 1, log)


    def test_17_committed_ledger_contract_star2_star3_star5(self):
        """저장소의 장부(versions.tsv): 머리 칸 = repack.LEDGER_COLUMNS · build 단조 증가 · host 는 sha8/.invalid · 키 모양 0."""
        sys.path.insert(0, str(HERE))
        import repack  # noqa: E402
        text = (rw.PACKAGING / "versions.tsv").read_text(encoding="utf-8")
        lines = [x for x in text.splitlines() if x.strip() and not x.startswith("#")]
        self.assertEqual(tuple(lines[0].split("\t")), repack.LEDGER_COLUMNS)
        builds = []
        for row in lines[1:]:
            cells = dict(zip(repack.LEDGER_COLUMNS, row.split("\t")))
            self.assertEqual(len(row.split("\t")), len(repack.LEDGER_COLUMNS), row[:40])
            builds.append(int(cells["windowsBuild"]))
            self.assertTrue(cells["prodHost"].startswith("sha8:") or cells["prodHost"].endswith(".invalid"), cells["prodHost"])
            self.assertNotRegex(row, "|".join(("ey" + "J", "sb" + "_publishable_", "sb" + "_secret_")))
        self.assertEqual(builds, sorted(set(builds)))
        self.assertTrue(all(1 <= b <= 65535 for b in builds))


if __name__ == "__main__":
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8", errors="backslashreplace")
        except (AttributeError, ValueError):
            pass
    result = unittest.main(argv=[sys.argv[0], "-v", *sys.argv[1:]], exit=False).result
    print(f"repack self-test: {result.testsRun} 사례 · 실패 {len(result.failures)} · 오류 {len(result.errors)}")
    sys.exit(0 if result.wasSuccessful() else 1)
