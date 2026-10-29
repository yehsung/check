#!/usr/bin/env python3
"""release_win.py 자가 시험(W6-b1 맥 JVM 몫, package.md §5). 실행: python3 -I multiplatform/desktopApp/packaging/release_win_selftest.py

표준 라이브러리만, 네트워크 0, 픽스처는 합성(임시 폴더)만. 저장소의 실제 원천(build-logic packageName · version.properties ·
identity · assets · 워크플로)은 읽기만 한다. 시험 이름의 ★n 은 release_win.py 머리의 규약 번호다.
"""
import io
import json
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

sys.dont_write_bytecode = True  # -I 는 PYTHONDONTWRITEBYTECODE 를 무시한다 — __pycache__ 를 저장소에 흘리지 않는다
sys.path.insert(0, str(Path(__file__).resolve().parent))  # -I 는 스크립트 폴더를 sys.path 에 넣지 않는다
import release_win as rw  # noqa: E402

KTS = rw.MP / "build-logic" / "src" / "main" / "kotlin" / "aingcheck.desktop-app.gradle.kts"
WORKFLOW = rw.REPO / ".github" / "workflows" / "mp-release-windows.yml"
SHA = "a" * 40
BUILD_TIME = "2026-10-30T01:02:03Z"


def template() -> str:
    return (rw.PACKAGING / "AppxManifest.template.xml").read_text(encoding="utf-8")


def dev_manifest(arch="x64") -> str:
    return rw.render_manifest(template(), rw.load_identity("dev"), rw.read_versions()["msixVersion"], arch)


def png(side: int) -> bytes:
    import struct
    import zlib
    raw = b"".join(b"\x00" + b"\x00\x00\x00\x00" * side for _ in range(side))
    chunk = lambda t, d: struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", side, side, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))


def jar_bytes(entries: dict) -> bytes:
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w") as z:
        for name, data in entries.items():
            z.writestr(name, data)
    return buf.getvalue()


def synthetic_layout(root: Path) -> Path:
    layout = root / "layout"
    (layout / "app").mkdir(parents=True)
    (layout / "runtime" / "bin").mkdir(parents=True)
    (layout / "AingCheck.exe").write_bytes(b"MZ-launcher")
    (layout / "runtime" / "bin" / "java.dll").write_bytes(b"jvm")
    (layout / "app" / "desktopApp-abc123.jar").write_bytes(
        jar_bytes({rw.APP_JAR_MARKER: b"id", "com/yehsung/aingcheck/desktop/MainKt.class": b"main"}))
    (layout / "app" / "core-def456.jar").write_bytes(jar_bytes({"com/yehsung/aingcheck/core/X.class": b"x"}))
    return layout


def selfcheck(**over) -> dict:
    v = rw.read_versions()
    base = {"platform": "windows", "build": v["windowsBuild"], "version": v["windowsVersion"], "buildTime": BUILD_TIME,
            "gitSha": SHA, "prodHost": "aingcheck.invalid", "prodKeySha8": "", "packageFamilyName": "AingCheck.Dev_abcd1234",
            "dataDir": r"C:\Users\r\AppData\Local\Packages\AingCheck.Dev_abcd1234\LocalCache\Local\aing-check"}
    base.update(over)
    return base


class VersionRules(unittest.TestCase):
    def test_star2_msix_version_bounds(self):
        self.assertEqual(rw.msix_version("1.0.65535"), "1.0.65535.0")
        self.assertEqual(rw.msix_version("255.255.0"), "255.255.0.0")
        for bad in ("1.0.65536", "256.0.1", "1.256.1", "1.0", "1.0.1.0", "1.0.x", "01.0.1", "-1.0.1", ""):
            with self.subTest(bad=bad), self.assertRaises(ValueError):
                rw.msix_version(bad)

    def test_star2_version_properties_build_is_third_field(self):
        v = rw.read_versions()
        self.assertEqual(v["windowsVersion"].split(".")[2], str(v["windowsBuild"]))
        self.assertTrue(v["msixVersion"].endswith(".0"))
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp) / "version.properties"
            p.write_text("windowsBuild=7\nwindowsVersion=1.0.6\n", encoding="utf-8")
            with self.assertRaises(ValueError):
                rw.read_versions(p)


class ManifestRules(unittest.TestCase):
    def test_render_leaves_no_placeholder(self):
        for arch in rw.ARCHES:
            with self.subTest(arch=arch):
                out = dev_manifest(arch)
                self.assertEqual(out.count("{{"), 0)
                self.assertIn(f'ProcessorArchitecture="{arch}"', out)
                self.assertIn('Name="AingCheck.Dev"', out)

    def test_render_rejects_unknown_placeholder_and_bad_arch_or_version(self):
        ident = rw.load_identity("dev")
        with self.assertRaises(ValueError):
            rw.render_manifest(template().replace("</Package>", "<!-- {{EXTRA}} --></Package>"), ident, "1.0.1.0", "x64")
        with self.assertRaises(ValueError):
            rw.render_manifest(template(), ident, "1.0.1.0", "x86")
        with self.assertRaises(ValueError):
            rw.render_manifest(template(), ident, "1.0.1.1", "x64")

    def test_render_escapes_values(self):
        ident = dict(rw.load_identity("dev"), displayName='A&"<B>')
        out = rw.render_manifest(template(), ident, "1.0.1.0", "x64")
        self.assertIn("A&amp;&quot;&lt;B&gt;", out)

    def test_executable_is_build_logic_package_name(self):
        name = rw.compose_package_name(KTS.read_text(encoding="utf-8"))
        facts = rw.manifest_facts(dev_manifest())
        self.assertEqual(facts["executables"], [name + ".exe"])

    def test_package_name_reader_ignores_comments(self):
        src = '// packageName = "Old"\n/* packageName = "Older" */\nnativeDistributions { packageName = "AingCheck" }\n' \
              'packageName.set("$appPackage.generated")'
        self.assertEqual(rw.compose_package_name(src), "AingCheck")
        with self.assertRaises(ValueError):
            rw.compose_package_name('packageName = "A"\npackageName = "B"')

    def test_application_alias_startup_task(self):
        facts = rw.manifest_facts(dev_manifest())
        self.assertEqual(facts["applicationIds"], [rw.APP_ID])
        self.assertEqual(facts["aliases"], [rw.ALIAS])
        self.assertEqual(facts["startupTasks"], [(rw.TASK_ID, "true")])  # 로그인 시 실행 기본 켬(CheckApp.swift:222-241)
        self.assertEqual(facts["backgroundColors"], ["transparent"])  # 색 리터럴은 매니페스트에 두지 않는다(D5)

    def test_manifest_logos_are_in_asset_table(self):
        for logo in rw.manifest_facts(dev_manifest())["logos"]:
            self.assertTrue(logo.startswith("Assets\\"), logo)
            self.assertIn(logo.split("\\", 1)[1], rw.ASSET_TABLE)


class IdentityRules(unittest.TestCase):
    def test_dev_identity_values(self):
        ident = rw.load_identity("dev")
        self.assertEqual((ident["name"], ident["publisher"]), ("AingCheck.Dev", "CN=AingCheck Dev Test"))

    def test_store_placeholder_rejected(self):
        with self.assertRaises(ValueError):
            rw.load_identity("store")

    def test_store_publisher_shape(self):
        good = "CN=0A1B2C3D-4E5F-6071-8293-A4B5C6D7E8F9"
        with tempfile.TemporaryDirectory() as tmp:
            def write(publisher, name="Yehsung.AingCheck", product="9NABCDEF1234"):
                (Path(tmp) / "store.properties").write_text(
                    f"name={name}\npublisher={publisher}\npublisherDisplayName=yehsung\ndisplayName=아잉체크\nproductId={product}\n",
                    encoding="utf-8")
            write(good)
            self.assertEqual(rw.load_identity("store", Path(tmp))["publisher"], good)
            write(good, product="__U7_STORE_PRODUCT_ID__")  # 다른 칸이 다 맞아도 자리표시 하나면 거부
            with self.assertRaises(ValueError):
                rw.load_identity("store", Path(tmp))
            for bad in (good.lower().replace("cn=", "CN="), "CN=AingCheck Dev Test", good + "0"):
                write(bad)
                with self.subTest(bad=bad), self.assertRaises(ValueError):
                    rw.load_identity("store", Path(tmp))
            write(good, name="bad name!")
            with self.assertRaises(ValueError):
                rw.load_identity("store", Path(tmp))


class AssetRules(unittest.TestCase):
    def test_asset_table_and_ico(self):
        self.assertEqual(rw.asset_violations(), [])

    def test_asset_checker_catches_wrong_size_missing_and_extra(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "assets").mkdir()
            for name, side in rw.ASSET_TABLE.items():
                (root / "assets" / name).write_bytes(png(side))
            (root / "AingCheck.ico").write_bytes(rw.ico_from_pngs([png(s) for s in rw.ICO_SIZES]))
            self.assertEqual(rw.asset_violations(root), [])
            (root / "assets" / "StoreLogo.png").write_bytes(png(44))
            self.assertEqual(len(rw.asset_violations(root)), 1)
            (root / "assets" / "StoreLogo.png").write_bytes(png(50))
            (root / "assets" / "Square150x150Logo.png").unlink()
            (root / "assets" / "Wide310x150Logo.png").write_bytes(png(10))
            self.assertEqual(len(rw.asset_violations(root)), 2)
            (root / "AingCheck.ico").write_bytes(rw.ico_from_pngs([png(s) for s in (16, 32, 256)]))
            self.assertEqual(len(rw.asset_violations(root)), 3)


class WorkflowRules(unittest.TestCase):
    def test_release_workflow_has_no_secrets_and_reads_only(self):
        self.assertEqual(rw.workflow_violations(WORKFLOW.read_text(encoding="utf-8")), [])

    def test_workflow_checker_negatives(self):
        ok = "name: x\npermissions:\n  contents: read\njobs:\n  a:\n    runs-on: ubuntu-24.04  # secrets. 는 주석이면 무시\n"
        self.assertEqual(rw.workflow_violations(ok), [])
        self.assertEqual(len(rw.workflow_violations(ok + "    env:\n      K: ${{ secrets.KEY }}\n")), 1)
        self.assertEqual(len(rw.workflow_violations(ok.replace("contents: read", "contents: write"))), 1)
        self.assertEqual(len(rw.workflow_violations(ok + "    permissions:\n      id-token: write\n")), 1)
        self.assertEqual(len(rw.workflow_violations(ok.replace("permissions:\n  contents: read\n", ""))), 1)


class ReceiptAndInstall(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.layout = synthetic_layout(self.root)
        self.wack = rw.wack_verdict(None, "auto", False)
        self.receipt = rw.build_receipt(self.layout, selfcheck(), rw.load_identity("dev"), "x64", SHA, BUILD_TIME,
                                        rw.read_versions(), self.wack)

    def tearDown(self):
        self.tmp.cleanup()

    def facts(self, **over):
        base = {"mode": "msix", "selfcheckExit": 0, "packageFamilyName": "AingCheck.Dev_abcd1234",
                "localAppData": r"C:\Users\r\AppData\Local", "installedJarSha256": self.receipt["appJar"]["sha256"],
                "installedPublisher": "CN=AingCheck Dev Test", "signerSubject": "CN=AingCheck Dev Test",
                "signerThumbprint": "ab" * 20, "expectedThumbprint": "AB" * 20, "remainingAfterRemove": 0}
        base.update(over)
        return base

    def test_receipt_shape(self):
        r = self.receipt
        self.assertEqual(r["schema"], rw.SCHEMA)
        self.assertEqual(r["appJar"]["name"], "app/desktopApp-abc123.jar")
        self.assertEqual({f["path"] for f in r["files"]},
                         {"AingCheck.exe", "runtime/bin/java.dll", "app/desktopApp-abc123.jar", "app/core-def456.jar"})
        self.assertEqual(r["prodHost"], "aingcheck.invalid")
        self.assertEqual(r["msixVersion"], rw.read_versions()["msixVersion"])

    def test_star1_receipt_refuses_other_build(self):
        ident, v = rw.load_identity("dev"), rw.read_versions()
        for over in ({"gitSha": "b" * 40}, {"buildTime": "dev"}, {"build": 999}, {"version": "9.9.9"}):
            with self.subTest(over=over), self.assertRaises(ValueError):
                rw.build_receipt(self.layout, selfcheck(**over), ident, "x64", SHA, BUILD_TIME, v, self.wack)
        with self.assertRaises(ValueError):
            rw.build_receipt(self.layout, selfcheck(), ident, "x64", "unknown", BUILD_TIME, v, self.wack)

    def test_star5_receipt_never_holds_real_host(self):
        self.assertEqual(rw.prod_host_for_receipt("AingCheck.invalid"), "aingcheck.invalid")
        hashed = rw.prod_host_for_receipt("abcdefgh.supabase.co")
        self.assertRegex(hashed, r"^sha8:[0-9a-f]{8}$")
        self.assertNotIn("supabase", hashed)
        with self.assertRaises(ValueError):  # dev 신원 패키지에 운영 구성이 들면 거부
            rw.build_receipt(self.layout, selfcheck(prodHost="abcdefgh.supabase.co"), rw.load_identity("dev"), "x64",
                             SHA, BUILD_TIME, rw.read_versions(), self.wack)

    def test_star1_install_check_ok(self):
        result = rw.check_install(self.receipt, selfcheck(), self.facts())
        self.assertTrue(result["ok"], result["failed"])

    def test_star1_install_check_each_mismatch_red(self):
        cases = {
            "gitSha": (selfcheck(gitSha="c" * 40), self.facts()),
            "buildTime": (selfcheck(buildTime="2026-01-01T00:00:00Z"), self.facts()),
            "build": (selfcheck(build=2), self.facts()),
            "prodHost": (selfcheck(prodHost="abcdefgh.supabase.co"), self.facts()),
            "pfn.identityName": (selfcheck(packageFamilyName="Other_abcd1234"), self.facts(packageFamilyName="Other_abcd1234")),
            "dataDir": (selfcheck(dataDir=r"C:\Users\r\AppData\Local\aing-check"), self.facts()),
            "appJar.sha256": (selfcheck(), self.facts(installedJarSha256="0" * 64)),
            "publisher.installed": (selfcheck(), self.facts(installedPublisher="CN=Someone Else")),
            "removed": (selfcheck(), self.facts(remainingAfterRemove=1)),
            "selfcheck.exit": (selfcheck(), self.facts(selfcheckExit="timeout")),
        }
        for cid, (sc, facts) in cases.items():
            with self.subTest(cid=cid):
                result = rw.check_install(self.receipt, sc, facts)
                self.assertFalse(result["ok"])
                self.assertIn(cid, result["failed"])
        self.assertFalse(rw.check_install(self.receipt, None, self.facts())["ok"])

    def test_star4_signer_must_be_this_runs_certificate(self):
        self.assertIn("signer.thumbprint", rw.check_install(self.receipt, selfcheck(), self.facts(signerThumbprint="cd" * 20))["failed"])
        self.assertIn("signer.thumbprint", rw.check_install(self.receipt, selfcheck(), self.facts(expectedThumbprint=""))["failed"])
        self.assertIn("signer.subject", rw.check_install(self.receipt, selfcheck(), self.facts(signerSubject="CN=X"))["failed"])
        loose = rw.check_install(self.receipt, selfcheck(), self.facts(mode="register", signerThumbprint="", expectedThumbprint=""))
        self.assertTrue(loose["ok"], loose["failed"])  # 느슨한 레이아웃(-Register)은 서명이 없다

    def test_cli_runner_negative_tampered_receipt(self):
        """러너 음성 대조와 같은 길: tamper-receipt → check-install 종료 1, ok=false, failed 에 gitSha."""
        exp, bad, sc, facts, out = (self.root / n for n in ("r.json", "bad.json", "sc.json", "facts.json", "ic.json"))
        exp.write_text(json.dumps(self.receipt), encoding="utf-8")
        sc.write_text("\ufeff" + json.dumps(selfcheck()), encoding="utf-8")  # PowerShell 5.1 BOM 도 읽는다
        facts.write_text(json.dumps(self.facts()), encoding="utf-8")
        quiet = io.StringIO()
        stdout, sys.stdout = sys.stdout, quiet
        try:
            self.assertEqual(rw.main(["check-install", "--expect", str(exp), "--selfcheck", str(sc), "--facts", str(facts), "--out", str(out)]), 0)
            self.assertEqual(rw.main(["tamper-receipt", "--in", str(exp), "--out", str(bad)]), 0)
            self.assertEqual(rw.main(["check-install", "--expect", str(bad), "--selfcheck", str(sc), "--facts", str(facts), "--out", str(out)]), 1)
        finally:
            sys.stdout = stdout
        result = json.loads(out.read_text(encoding="utf-8"))
        self.assertFalse(result["ok"])
        self.assertEqual(result["failed"], ["gitSha"])

    def test_find_app_jar_must_be_unique(self):
        (self.layout / "app" / "dup.jar").write_bytes(jar_bytes({rw.APP_JAR_MARKER: b"2"}))
        with self.assertRaises(ValueError):
            rw.find_app_jar(self.layout / "app")

    def test_bundle_plan_consistency(self):
        arm = dict(self.receipt, arch="arm64")
        plan = rw.bundle_plan([self.receipt, arm])
        self.assertEqual(plan["arches"], ["arm64", "x64"])
        for bad in ([self.receipt, self.receipt], [self.receipt, dict(arm, gitSha="d" * 40)],
                    [self.receipt, dict(arm, identity={"name": "X", "publisher": "CN=Y", "mode": "dev"})]):
            with self.assertRaises(ValueError):
                rw.bundle_plan(bad)


class WackRules(unittest.TestCase):
    XML = ('<REPORT OVERALL_RESULT="{o}"><REQUIREMENTS><REQUIREMENT><TEST NAME="Clean reversible install"><RESULT><![CDATA[PASS]]></RESULT></TEST>'
           '<TEST NAME="{n}" {opt}><RESULT><![CDATA[{r}]]></RESULT></TEST></REQUIREMENT></REQUIREMENTS></REPORT>')

    def test_verdicts(self):
        x = lambda o, r, opt="", n="Blocked executables": self.XML.format(o=o, r=r, opt=opt, n=n)
        self.assertTrue(rw.wack_verdict(x("PASS", "PASS"), "require", True)["ok"])
        v = rw.wack_verdict(x("FAIL", "FAIL", 'OPTIONAL="TRUE"'), "require", True)
        self.assertTrue(v["ok"])  # 선택 시험 FAIL 은 기록만
        self.assertEqual(v["optionalFailed"], ["Blocked executables"])
        self.assertFalse(rw.wack_verdict(x("FAIL", "FAIL", n="Digital signature"), "require", True)["ok"])
        self.assertFalse(rw.wack_verdict(None, "require", True)["ok"])
        self.assertFalse(rw.wack_verdict(None, "require", False)["ok"])
        self.assertTrue(rw.wack_verdict(None, "auto", False)["ok"])  # arm64: available=false 를 기록
        self.assertFalse(rw.wack_verdict(None, "auto", False)["available"])


class MacRepackRules(unittest.TestCase):
    def test_jar_diff_allows_only_generated(self):
        with tempfile.TemporaryDirectory() as tmp:
            a, b, c = (Path(tmp) / n for n in ("a.jar", "b.jar", "c.jar"))
            base = {rw.GENERATED_PREFIX + "ProdConfig.class": b"invalid", "com/yehsung/aingcheck/desktop/MainKt.class": b"m"}
            a.write_bytes(jar_bytes(base))
            b.write_bytes(jar_bytes(dict(base, **{rw.GENERATED_PREFIX + "ProdConfig.class": b"prod"})))
            c.write_bytes(jar_bytes(dict(base, **{"com/yehsung/aingcheck/desktop/MainKt.class": b"m2"})))
            self.assertEqual(rw.jar_diff(a, b), {"ok": True, "changed": [rw.GENERATED_PREFIX + "ProdConfig.class"], "outside": []})
            self.assertFalse(rw.jar_diff(a, c)["ok"])
            self.assertTrue(rw.jar_diff(a, a)["ok"])

    def test_ledger_next_ok(self):
        tsv = "# 장부\nwindowsBuild\twindowsVersion\tgitSha\n3\t1.0.3\tx\n5\t1.0.5\ty\n"
        self.assertTrue(rw.ledger_next_ok(6, tsv))
        self.assertFalse(rw.ledger_next_ok(5, tsv))
        self.assertFalse(rw.ledger_next_ok(4, tsv))
        self.assertTrue(rw.ledger_next_ok(1, ""))
        self.assertFalse(rw.ledger_next_ok(2, "2\t1.0.2\n"))


if __name__ == "__main__":
    unittest.main(verbosity=1)
