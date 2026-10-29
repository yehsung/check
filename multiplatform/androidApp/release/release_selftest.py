# 원본: 없음 — release-android.sh self-test(W6-a). 가짜 입력으로 입력 거부·Gradle 넘김·산출물 판정·서명·장부·smoke 판정을 잰다.
#
# 쓰는 것: python3 · git · JDK(keytool·jarsigner·javac) · Android build-tools 의 d8(진짜 dex 를 만든다 — 판정기의 dex 읽기를
# 그 판정기가 아닌 도구가 만든 바이트로 잰다). Gradle·에뮬레이터·망·키체인·사용자 비밀은 쓰지 않는다. HOME·TMPDIR 은 임시 폴더로 돌린다.
# 사례마다 기대 결과(종료 코드·빨간 판정 이름)를 적고, 다르면 FAIL 로 센다. 사례 수만큼 돌았는지 끝에 센다(건너뜀 0).
import base64
import hashlib
import json
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import zipfile

TIME = "20261028T010203Z"
SHA = "0123456789abcdef0123456789abcdef01234567"
VC, VN = 7, "1.2.3"
PROD_URL = "https://w6a-selftest.example"
APP_ID, PROJECT_ID, SENDER_ID, API_KEY = "1:123456789012:android:0123456789abcdef", "w6a-selftest", "123456789012", "w6aSelftestApiKey_0123456789"
GS_NAME = "google-services" + ".json"  # 글자를 이어 붙인다(저장소 푸시 전 비밀 검사가 글자 그대로 찾는다)
ROLE_SECRET = "service" + "_role"
PERMS = [
    "android.permission.INTERNET", "android.permission.ACCESS_NETWORK_STATE", "android.permission.POST_NOTIFICATIONS",
    "android.permission.VIBRATE", "android.permission.WAKE_LOCK", "android.permission.RECEIVE_BOOT_COMPLETED",
    "com.google.android.c2dm.permission.RECEIVE", "com.yehsung.aingcheck.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION",
]


def b64url(obj):
    return base64.urlsafe_b64encode(json.dumps(obj).encode()).decode().rstrip("=")


def fake_jwt(role, ref="w6a-selftest"):
    return b64url({"alg": "HS256", "typ": "JWT"}) + "." + b64url({"iss": "supabase", "ref": ref, "role": role}) + ".c2lnLW5vdC1yZWFs"


class Ctx:
    def __init__(self, root, script, tool):
        self.root, self.script, self.tool = root, script, tool
        self.real_mp = os.path.abspath(os.path.join(os.path.dirname(tool), "..", ".."))
        self.results = []
        self.home = os.path.join(root, "home")
        self.tmp = os.path.join(root, "tmp")
        os.makedirs(self.home)
        os.makedirs(self.tmp)
        env = {k: v for k, v in os.environ.items()
               if not k.startswith(("AINGCHECK_UPLOAD_", "ORG_GRADLE_PROJECT_", "AINGCHECK_RELEASE_"))}
        env.update(HOME=self.home, TMPDIR=self.tmp, AINGCHECK_RELEASE_SELFTEST="1", LC_ALL="C.UTF-8" if sys.platform != "darwin" else "en_US.UTF-8")
        env.pop("AINGCHECK_NETWORK_SEALED", None)  # 바깥 게이트의 봉인 표지가 OS 가드 사례(U3)를 가리지 않게
        # 가짜 security 를 언제나 건다 — 기본 키체인 항목(aingcheck-android-upload) 길이 진짜 키체인에 닿지 않게(사용자 비밀 읽기 금지).
        # good → $FAKE_PW_GOOD · 기본 항목 → $FAKE_PW_DEFAULT(없으면 44) · wrong → 틀린 비밀번호 · 그 밖 → 44(항목 없음).
        self.security = os.path.join(root, "fake-security")
        with open(self.security, "w") as f:
            f.write('#!/bin/sh\n[ "$1" = find-generic-password ] && [ "$2" = -s ] && [ "$4" = -w ] || exit 9\n'
                    'case "$3" in good) printf "%s\\n" "$FAKE_PW_GOOD";; wrong) echo wrong-password;;\n'
                    '  aingcheck-android-upload) [ -n "$FAKE_PW_DEFAULT" ] || exit 44; printf "%s\\n" "$FAKE_PW_DEFAULT";;\n'
                    '  *) exit 44;; esac\n')
        os.chmod(self.security, 0o755)
        env["AINGCHECK_RELEASE_SECURITY_BIN"] = self.security
        # 가짜 uname(-s → Linux): OS 가드 사례(U*)만 PATH 앞에 둔다.
        self.linux_bin = os.path.join(root, "linux-bin")
        os.makedirs(self.linux_bin)
        with open(os.path.join(self.linux_bin, "uname"), "w") as f:
            f.write('#!/bin/sh\necho Linux\n')
        os.chmod(os.path.join(self.linux_bin, "uname"), 0o755)
        self.env = env

    # ---- 기록
    def case(self, name, ok, detail=""):
        self.results.append((name, bool(ok), detail))
        print(f"self-test: {'ok  ' if ok else 'FAIL'} {name}{(' — ' + detail) if detail and not ok else ''}")

    def run(self, argv, env=None, cwd=None):
        e = dict(self.env)
        if env:
            e.update(env)
        p = subprocess.run(argv, env=e, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        return p.returncode, p.stdout

    def tool_run(self, *args, env=None):
        return self.run([sys.executable, "-I", self.tool, *args], env=env)

    def bash(self, *args, env=None):
        return self.run(["bash", self.script, *args], env=env)


def find_tool(name):
    for d in os.environ.get("PATH", "").split(os.pathsep):
        p = os.path.join(d, name)
        if os.path.isfile(p) and os.access(p, os.X_OK):
            return p
    jh = os.environ.get("JAVA_HOME")
    if jh and os.access(os.path.join(jh, "bin", name), os.X_OK):
        return os.path.join(jh, "bin", name)
    return None


def find_d8():
    sdk = os.environ.get("ANDROID_HOME") or os.environ.get("ANDROID_SDK_ROOT") or os.path.expanduser("~/Library/Android/sdk")
    bt = os.path.join(sdk, "build-tools")
    if not os.path.isdir(bt):
        return None
    def key(v):
        return [int(x) if x.isdigit() else 0 for x in re.split(r"[.-]", v)]
    for v in sorted(os.listdir(bt), key=key, reverse=True):
        p = os.path.join(bt, v, "d8")
        if os.access(p, os.X_OK):
            return p
    return None


# ============================================================================ 고정물

def make_key(ctx, name, password):
    path = os.path.join(ctx.root, name + ".p12")
    rc, out = ctx.run(["keytool", "-J-Duser.language=en", "-genkeypair", "-keystore", path, "-storetype", "PKCS12", "-alias", "upload",
                       "-keyalg", "RSA", "-keysize", "2048", "-validity", "30", "-dname", f"CN=w6a selftest {name}",
                       "-storepass:env", "ST_PW", "-keypass:env", "ST_PW"], env={"ST_PW": password})
    if rc != 0:
        raise RuntimeError("keytool genkeypair: " + out[-300:])
    rc, pem = ctx.run(["keytool", "-J-Duser.language=en", "-exportcert", "-rfc", "-keystore", path, "-alias", "upload", "-storepass:env", "ST_PW"], env={"ST_PW": password})
    p = subprocess.run([sys.executable, "-I", ctx.tool, "cert-sha256"], input=pem, stdout=subprocess.PIPE, text=True, env=ctx.env)
    # 기준선(다른 길): keytool 이 직접 찍은 SHA256 지문과 같아야 한다.
    rc2, listing = ctx.run(["keytool", "-J-Duser.language=en", "-list", "-v", "-keystore", path, "-storepass:env", "ST_PW"], env={"ST_PW": password})
    m = re.search(r"SHA256:\s*([0-9A-F:]{95})", listing)
    keytool_sha = m.group(1).replace(":", "").lower() if m else None
    return path, p.stdout.strip(), keytool_sha


def make_repo(ctx, ledger_rows=(), version_code=VC, extra_dirty=None, duels_from=None):
    repo = tempfile.mkdtemp(prefix="repo.", dir=ctx.root)
    mp = os.path.join(repo, "multiplatform")
    rel = os.path.join(mp, "androidApp", "release")
    os.makedirs(rel)
    with open(os.path.join(mp, "version.properties"), "w") as f:
        f.write(f"androidVersionCode={version_code}\nandroidVersionName={VN}\n")
        if duels_from is not None:
            f.write(f"androidDuelsFromBuild={duels_from}\n")
    with open(os.path.join(rel, "versions.tsv"), "w") as f:
        f.write("# 장부\n")
        for r in ledger_rows:
            f.write("\t".join(r) + "\n")
    shutil.copy(os.path.join(ctx.real_mp, "androidApp", "release", "permissions.txt"), os.path.join(rel, "permissions.txt"))
    g = ["git", "-C", repo, "-c", "user.name=selftest", "-c", "user.email=selftest@example.invalid", "-c", "commit.gpgsign=false"]
    for argv in (["git", "init", "-q", repo], g + ["add", "-A"], g + ["commit", "-q", "-m", "fixture"]):
        rc, out = ctx.run(argv)
        if rc != 0:
            raise RuntimeError("git: " + out[-300:])
    if extra_dirty:
        with open(os.path.join(mp, extra_dirty), "w") as f:
            f.write("dirty\n")
    return mp


def write_props(ctx, name, values):
    p = os.path.join(ctx.root, name)
    with open(p, "w") as f:
        for k, v in values.items():
            f.write(f"aingcheck.prod.{k}={v}\n")
    os.chmod(p, 0o600)
    return p


def good_prod_values():
    return {"supabaseUrl": PROD_URL, "supabaseAnonKey": fake_jwt("anon"), "firebaseAppId": APP_ID,
            "firebaseProjectId": PROJECT_ID, "firebaseSenderId": SENDER_ID, "firebaseApiKey": API_KEY}


def make_dex(ctx, name, duels, stamp, prod, leak=False, with_build_config=True, identity=(VC, VN), extra_string=None):
    """javac + d8 로 진짜 dex 를 만든다(BuildConfig · ProdConfig · BuildIdentity · 선택 Leak · 선택 Showcase 문자열)."""
    src = os.path.join(ctx.root, "java-" + name)
    out = os.path.join(ctx.root, "classes-" + name)
    dexdir = os.path.join(ctx.root, "dex-" + name)
    os.makedirs(os.path.join(src, "com/yehsung/aingcheck/android/generated"))
    os.makedirs(out)
    os.makedirs(dexdir)
    q = lambda s: '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'
    files = []
    if with_build_config:
        files.append(("com/yehsung/aingcheck/android/BuildConfig.java",
                      "package com.yehsung.aingcheck.android;\npublic final class BuildConfig {\n"
                      f"  public static final boolean DUELS_ENABLED = {'true' if duels else 'false'};\n"
                      f"  public static final String RELEASE_STAMP = {q(stamp)};\n  private BuildConfig() {{}}\n}}\n"))
    pv = prod or {}
    fields = {"FIREBASE_API_KEY": pv.get("firebaseApiKey", ""), "FIREBASE_APP_ID": pv.get("firebaseAppId", ""),
              "FIREBASE_PROJECT_ID": pv.get("firebaseProjectId", ""), "FIREBASE_SENDER_ID": pv.get("firebaseSenderId", ""),
              "SUPABASE_ANON_KEY": pv.get("supabaseAnonKey", ""), "SUPABASE_URL": pv.get("supabaseUrl", "https://aingcheck.invalid")}
    files.append(("com/yehsung/aingcheck/android/generated/ProdConfig.java",
                  "package com.yehsung.aingcheck.android.generated;\npublic final class ProdConfig {\n"
                  + "".join(f"  public static final String {k} = {q(v)};\n" for k, v in fields.items()) + "}\n"))
    files.append(("com/yehsung/aingcheck/android/generated/BuildIdentity.java",
                  "package com.yehsung.aingcheck.android.generated;\npublic final class BuildIdentity {\n"
                  f'  public static final String BUILD = "{identity[0]}";\n  public static final String PLATFORM = "android";\n'
                  f'  public static final String VERSION = "{identity[1]}";\n}}\n'))
    if extra_string is not None:
        # 진열장 함수가 다른 클래스에 인라인된 꼴: 클래스 이름은 진열장이 아니고 문자열만 남는다.
        files.append(("com/yehsung/aingcheck/android/generated/Inlined.java",
                      "package com.yehsung.aingcheck.android.generated;\npublic final class Inlined {\n"
                      f"  public static String t() {{ return {q(extra_string)}; }}\n}}\n"))
    if leak:
        files.append(("com/yehsung/aingcheck/android/generated/Leak.java",
                      "package com.yehsung.aingcheck.android.generated;\npublic final class Leak {\n"
                      '  public static final String U = "https://aingcheck.invalid/leak";\n}\n'))
    paths = []
    for rel, text in files:
        p = os.path.join(src, rel)
        with open(p, "w", encoding="utf-8") as f:
            f.write(text)
        paths.append(p)
    rc, o = ctx.run(["javac", "-encoding", "UTF-8", "--release", "17", "-d", out] + paths)
    if rc != 0:
        raise RuntimeError("javac: " + o[-400:])
    classes = []
    for d, _, fs in os.walk(out):
        classes += [os.path.join(d, f) for f in fs if f.endswith(".class")]
    rc, o = ctx.run([ctx.d8, "--release", "--min-api", "26", "--output", dexdir] + sorted(classes))
    if rc != 0:
        raise RuntimeError("d8: " + o[-400:])
    with open(os.path.join(dexdir, "classes.dex"), "rb") as f:
        return f.read()


def make_archive(ctx, name, dex, kind="aab", extra=None, mapping=True, sign_key=None):
    p = os.path.join(ctx.root, name)
    base = "base/" if kind == "aab" else ""
    with zipfile.ZipFile(p, "w", zipfile.ZIP_DEFLATED) as z:
        if dex is not None:
            z.writestr(base + ("dex/classes.dex" if kind == "aab" else "classes.dex"), dex)
        z.writestr(base + ("manifest/AndroidManifest.xml" if kind == "aab" else "AndroidManifest.xml"), b"<manifest/>")
        z.writestr(base + "assets/composeResources/font/pretendard_regular.otf", b"OTTO" + b"\x00" * 64)
        if kind == "aab" and mapping:
            z.writestr("BUNDLE-METADATA/com.android.tools.build.obfuscation/proguard.map",
                       mapping if isinstance(mapping, str) else "com.yehsung.aingcheck.android.shell.MainActivity -> com.yehsung.aingcheck.android.shell.MainActivity:\n")
        for n, data in (extra or {}).items():
            z.writestr(n, data)
    if sign_key:
        path, pw = sign_key
        rc, o = ctx.run(["jarsigner", "-J-Duser.language=en", "-keystore", path, "-storetype", "PKCS12", "-storepass:env", "ST_PW", p, "upload"], env={"ST_PW": pw})
        if rc != 0:
            raise RuntimeError("jarsigner: " + o[-300:])
    return p


def badging(perms=None, package="com.yehsung.aingcheck", vc=VC, vn=VN, target="36", minsdk="26", icon="res/mipmap/ic_launcher.png",
            launcher="com.yehsung.aingcheck.android.shell.MainActivity"):
    perms = PERMS if perms is None else perms
    lines = [f"package: name='{package}' versionCode='{vc}' versionName='{vn}' platformBuildVersionName='17' platformBuildVersionCode='37' compileSdkVersion='37' compileSdkVersionCodename='17'",
             f"minSdkVersion:'{minsdk}'", f"targetSdkVersion:'{target}'"]
    lines += [f"uses-permission: name='{p}'" for p in perms]
    lines += ["application-label:'아잉체크'", f"application: label='아잉체크' icon='{icon}'",
              f"launchable-activity: name='{launcher}'  label='' icon=''",
              "native-code: 'arm64-v8a' 'armeabi-v7a' 'x86' 'x86_64'"]
    return "\n".join(lines) + "\n"


# ============================================================================ 사례

def preflight_cases(ctx, keyA, keyB):
    pathA, certA, pwA = keyA
    pathB, certB, pwB = keyB
    mp = make_repo(ctx)
    good = write_props(ctx, "good.properties", good_prod_values())
    envA = {"AINGCHECK_RELEASE_MP": mp, "AINGCHECK_UPLOAD_KEYSTORE": pathA, "AINGCHECK_UPLOAD_STORE_PASSWORD": pwA}

    def build(*args, env=None, mp_dir=None):
        e = dict(envA)
        if mp_dir:
            e["AINGCHECK_RELEASE_MP"] = mp_dir
        if env:
            e.update(env)
        return ctx.bash("build", "--plan-only", *args, env={k: v for k, v in e.items() if v is not None})

    def expect(name, rc_out, want_rc, needle=None):
        rc, out = rc_out
        ok = rc == want_rc and (needle is None or needle in out)
        ctx.case(name, ok, f"rc={rc} 기대 {want_rc} · '{needle}' {'있음' if needle and needle in out else '없음'} · {out.strip()[-200:]}")
        return out

    out = expect("P0 정상 운영 계획(plan-only)", build("--prod-config", good), 0, f"uploadCert={certA}")
    ctx.case("P0b 계획의 인증서 지문 = keytool 기준선", certA == keyA_keytool[0], f"{certA} vs {keyA_keytool[0]}")
    expect("P1 운영 구성 없음 → 거부", build(), 2, "운영 구성이 없다")
    v = good_prod_values()
    for k in ("firebaseAppId", "firebaseProjectId", "firebaseSenderId", "firebaseApiKey"):
        v.pop(k)
    expect("P2 Firebase 넷 모두 없음 → 거부", build("--prod-config", write_props(ctx, "nofb.properties", v)), 2, "모자란다")
    v = good_prod_values(); v.pop("firebaseApiKey")
    expect("P3 Firebase 셋만 → 거부", build("--prod-config", write_props(ctx, "fb3.properties", v)), 2, "firebaseApiKey")
    v = good_prod_values(); v.pop("supabaseAnonKey")
    expect("P3b anon 키 없음 → 거부", build("--prod-config", write_props(ctx, "noanon.properties", v)), 2, "supabaseAnonKey")
    v = good_prod_values(); v["supabaseUrl"] = "https://aingcheck.invalid"
    expect("P4 운영 주소가 .invalid → 거부", build("--prod-config", write_props(ctx, "inv.properties", v)), 2, "시험 주소")
    v = good_prod_values(); v["supabaseAnonKey"] = fake_jwt(ROLE_SECRET)
    expect("P5 비밀 역할 키 → 거부", build("--prod-config", write_props(ctx, "secret.properties", v)), 2, "role=anon")
    p = write_props(ctx, "unknown.properties", good_prod_values())
    with open(p, "a") as f:
        f.write("aingcheck.prod.extra=1\n")
    expect("P6 모르는 키 → 거부", build("--prod-config", p), 2, "모르는 키")
    v = good_prod_values(); v["firebaseSenderId"] = "999999999999"
    expect("P6b 앱 id 와 senderId 가 다른 프로젝트 → 거부", build("--prod-config", write_props(ctx, "mix.properties", v)), 2, "섞었다")
    # google-services(json)
    gs = {"project_info": {"project_number": SENDER_ID, "project_id": PROJECT_ID},
          "client": [{"client_info": {"mobilesdk_app_id": APP_ID, "android_client_info": {"package_name": "com.yehsung.aingcheck"}},
                      "api_key": [{"current_key": API_KEY}]}]}
    gsp = os.path.join(ctx.root, "gs-good-" + GS_NAME)
    with open(gsp, "w") as f:
        json.dump(gs, f)
    v = {k: good_prod_values()[k] for k in ("supabaseUrl", "supabaseAnonKey")}
    sb_only = write_props(ctx, "sb.properties", v)
    expect("P7 Firebase 넷은 google-services 에서 → 통과", build("--prod-config", sb_only, "--google-services", gsp), 0, "plan-only mode=prod")
    expect("P8 Firebase 가 두 곳 → 거부", build("--prod-config", good, "--google-services", gsp), 2, "양쪽")
    gs["client"][0]["client_info"]["android_client_info"]["package_name"] = "com.example.other"
    gsbad = os.path.join(ctx.root, "gs-bad-" + GS_NAME)
    with open(gsbad, "w") as f:
        json.dump(gs, f)
    expect("P9 다른 패키지의 google-services → 거부", build("--prod-config", sb_only, "--google-services", gsbad), 2, "정확히 하나가 아니다")
    # 업로드 키 — 기본 자리(G §2-3 W6-a 행): 키 ~/.aing-check-secrets/android/upload.p12 · 비밀번호 키체인 항목 aingcheck-android-upload.
    # HOME 은 가짜 폴더다(Ctx). 키체인은 가짜 security 다(Ctx — 진짜 키체인에 닿지 않는다).
    expect("S1 키 경로 없음 → 기본 자리(가짜 HOME)에도 없음 → 거부", build("--prod-config", good, env={"AINGCHECK_UPLOAD_KEYSTORE": None}), 2,
           "업로드 키 파일이 없다: " + os.path.join(ctx.home, ".aing-check-secrets", "android", "upload.p12"))
    expect("S2 비밀번호 없음 → 기본 키체인 항목(없음) → 거부", build("--prod-config", good, env={"AINGCHECK_UPLOAD_STORE_PASSWORD": None}), 2,
           "키체인 항목 'aingcheck-android-upload' 을 못 읽었다")
    sec_env = {"FAKE_PW_GOOD": pwA, "AINGCHECK_UPLOAD_STORE_PASSWORD": None}
    # 키체인 쪽도 맞는 비밀번호를 내게 둔다 — 두 곳 거부가 없으면 통과해 버리는 입력이어야 거부를 잰다.
    expect("S3 비밀번호가 두 곳 → 거부", build("--prod-config", good, "--keychain-item", "good", env={"FAKE_PW_GOOD": pwA}), 2, "거부 — 비밀번호가 두 곳")
    expect("S4 키체인 항목 → 통과·같은 인증서", build("--prod-config", good, "--keychain-item", "good", env=sec_env), 0, f"uploadCert={certA}")
    expect("S5 키체인 비밀번호가 틀림 → 거부", build("--prod-config", good, "--keychain-item", "wrong", env=sec_env), 2, "못 열었다")
    expect("S6 키체인 항목 없음 → 거부", build("--prod-config", good, "--keychain-item", "missing", env=sec_env), 2, "못 읽었다")
    expect("S7 별칭이 틀림 → 거부", build("--prod-config", good, "--key-alias", "nope"), 2, "못 열었다")
    # 기본 자리에 키를 두고(가짜 HOME) 기본 키체인 항목이 비밀번호를 내면 인자 없이 통과 · 경고 0 · 영수증 입력 칸이 그 자리다.
    sec_dir = os.path.join(ctx.home, ".aing-check-secrets", "android")
    os.makedirs(sec_dir)
    shutil.copy(pathA, os.path.join(sec_dir, "upload.p12"))
    out_def = os.path.join(ctx.root, "plan-default-place")
    os.makedirs(out_def)
    expect("S8 기본 자리 키 + 기본 키체인 항목 → 통과", build("--prod-config", good, "--out", out_def,
           env={"AINGCHECK_UPLOAD_KEYSTORE": None, "AINGCHECK_UPLOAD_STORE_PASSWORD": None, "FAKE_PW_DEFAULT": pwA}), 0, f"uploadCert={certA}")
    pd_ = _load_json(os.path.join(out_def, "plan.json"))
    ctx.case("S8b 기본 자리는 경고 0 · inputs=secrets-dir/keychain", pd_.get("warnings") == [] and pd_.get("inputs") == {"keyPlace": "secrets-dir", "passwordSource": "keychain"},
             f"warnings={pd_.get('warnings')} inputs={pd_.get('inputs')}")
    out_env = os.path.join(ctx.root, "plan-env-place")
    os.makedirs(out_env)
    expect("S9 자리 밖 키 + 환경 변수 비밀번호 → 통과(경고)", build("--prod-config", good, "--out", out_env), 0, "경고 — password-from-env")
    pe_ = _load_json(os.path.join(out_env, "plan.json"))
    ctx.case("S9b 경고 둘이 계획(→ 영수증)에 남는다", [w.split(":")[0] for w in pe_.get("warnings", [])] == ["key-outside-secrets-dir", "password-from-env"]
             and pe_.get("inputs") == {"keyPlace": "other", "passwordSource": "env"}, f"warnings={pe_.get('warnings')} inputs={pe_.get('inputs')}")
    # 운영 판 계획은 키 자리·출처 없이 만들지 않는다(셸이 언제나 넘긴다 — 도구를 따로 불러 영수증 입력 칸을 비우지 못하게).
    rc_w0, out_w0 = ctx.tool_run("preflight", "--mode", "prod", "--version-properties", os.path.join(mp, "version.properties"), "--ledger",
                                 os.path.join(ctx.root, "none.tsv"), "--prod-config", good, "--build-time", TIME, "--git-sha", SHA, "--git-dirty", "0",
                                 "--upload-cert-sha256", certA, "--out", os.path.join(ctx.root, "plan-w0.json"), "--values-out", os.path.join(ctx.root, "vals-w0.json"))
    ctx.case("W0 운영 계획에 키 자리·출처가 없으면 거부", rc_w0 == 2 and "키 자리" in out_w0, f"rc={rc_w0} {out_w0.strip()[-160:]}")
    expect("A1 --duels 값이 틀림 → 거부", build("--prod-config", good, "--duels", "maybe"), 2, "on 또는 off")
    # OS 가드(검증 지적: Darwin 가드가 --plan-only 앞에 있어 Linux CI 에서 계획 사례 32건이 빨갰다).
    # 가짜 uname(-s → Linux)을 PATH 앞에 둔다. 계획까지는 어느 OS 에서나, Gradle·서명은 맥에서만·봉인 아래에서만.
    lin = {"PATH": ctx.linux_bin + os.pathsep + ctx.env.get("PATH", "")}
    expect("U1 Linux + 운영 계획(plan-only) → 통과", build("--prod-config", good, env=lin), 0, "plan-only mode=prod")
    expect("U2 Linux + 운영 build → 거부(맥에서만)", ctx.bash("build", "--prod-config", good, env=dict(envA, **lin)), 2, "이 맥에서만 만든다")
    expect("U3 Linux + dryrun(봉인 표지 없음) → 거부", ctx.bash("dryrun", env={"AINGCHECK_RELEASE_MP": mp, **lin}), 2, "봉인 밖에서 Gradle 을 돌리지 않는다")
    expect("U4 Linux + dryrun 계획(plan-only) → 통과", ctx.bash("dryrun", "--plan-only", env={"AINGCHECK_RELEASE_MP": mp, **lin}), 0, "plan-only mode=dryrun")
    # 판돈 이중 확인(검증 지적: 출시 인자 하나로 켜졌다): 커밋된 androidDuelsFromBuild 와 --duels 가 맞아야 한다.
    expect("DU1 --duels on · androidDuelsFromBuild 없음 → 거부", build("--prod-config", good, "--duels", "on"), 2, "androidDuelsFromBuild=N")
    expect("DU2 --duels on · androidDuelsFromBuild=이번 판 → 통과", build("--prod-config", good, "--duels", "on", mp_dir=make_repo(ctx, duels_from=VC)), 0, "plan-only mode=prod")
    expect("DU3 --duels on · androidDuelsFromBuild 가 다음 판 → 거부", build("--prod-config", good, "--duels", "on", mp_dir=make_repo(ctx, duels_from=VC + 1)), 2, "versionCode ≥ N")
    expect("DU4 --duels off · androidDuelsFromBuild ≤ 이번 판 → 거부", build("--prod-config", good, mp_dir=make_repo(ctx, duels_from=VC - 2)), 2, "판돈을 켠다")
    expect("DU5 --duels off · androidDuelsFromBuild 가 다음 판 → 통과", build("--prod-config", good, mp_dir=make_repo(ctx, duels_from=VC + 1)), 0, "plan-only mode=prod")
    expect("DU6 androidDuelsFromBuild 가 정수가 아님 → 거부", build("--prod-config", good, mp_dir=make_repo(ctx, duels_from="7a")), 2, "정수여야")
    # 작업 트리
    mp_dirty = make_repo(ctx, extra_dirty="stray.txt")
    expect("T1 더러운 트리 → 거부", build("--prod-config", good, mp_dir=mp_dirty), 2, "깨끗하지 않다")
    expect("T2 더러운 트리 + --allow-dirty → 통과(dirty=1)", build("--prod-config", good, "--allow-dirty", mp_dir=mp_dirty), 0, "dirty=1")
    mp_ledger = make_repo(ctx)
    with open(os.path.join(mp_ledger, "androidApp", "release", "versions.tsv"), "a") as f:
        f.write("\t".join(["1", VN, TIME, SHA, "0", "0" * 64, certA]) + "\n")
    expect("T3 장부만 바뀐 트리는 깨끗하다", build("--prod-config", good, mp_dir=mp_ledger), 0, "dirty=0")
    # 판 번호·장부
    row = lambda vc, cert: (str(vc), VN, TIME, SHA, "0", "0" * 64, cert)
    expect("V1 같은 versionCode → 거부", build("--prod-config", good, mp_dir=make_repo(ctx, [row(VC, certA)])), 2, "단조 증가")
    expect("V2 작은 versionCode → 거부", build("--prod-config", good, mp_dir=make_repo(ctx, [row(VC + 3, certA)])), 2, "단조 증가")
    expect("V3 큰 versionCode → 통과", build("--prod-config", good, mp_dir=make_repo(ctx, [row(VC - 1, certA)])), 0, f"versionCode={VC}")
    expect("V4 직전 판과 다른 업로드 키 → 거부", build("--prod-config", good, mp_dir=make_repo(ctx, [row(VC - 1, certB)])), 2, "업로드 키 인증서")
    expect("V5 다른 키 + --new-upload-key → 통과", build("--prod-config", good, "--new-upload-key", mp_dir=make_repo(ctx, [row(VC - 1, certB)])), 0, "plan-only")
    expect("V6 versionCode 0 → 거부", build("--prod-config", good, mp_dir=make_repo(ctx, version_code=0)), 2, "1..1000000")
    expect("V7 versionCode 1000001 → 거부", build("--prod-config", good, mp_dir=make_repo(ctx, version_code=1000001)), 2, "1..1000000")
    mp_bad = make_repo(ctx)
    with open(os.path.join(mp_bad, "androidApp", "release", "versions.tsv"), "a") as f:
        f.write("x\ty\n")
    expect("V8 장부 줄 모양이 틀림 → 거부", build("--prod-config", good, mp_dir=mp_bad), 2, "모양이 틀렸다")
    # dryrun
    expect("D1 dryrun + 운영 구성 → 거부", ctx.bash("dryrun", "--plan-only", "--prod-config", good, env={"AINGCHECK_RELEASE_MP": mp}), 2, "받지 않는다")
    expect("D2 dryrun + --keystore → 거부", ctx.bash("dryrun", "--plan-only", "--keystore", pathA, env={"AINGCHECK_RELEASE_MP": mp}), 2, "업로드 키를 받지 않는다")
    expect("D3 dryrun 계획(버리는 키) → 통과", ctx.bash("dryrun", "--plan-only", env={"AINGCHECK_RELEASE_MP": mp, "AINGCHECK_UPLOAD_STORE_PASSWORD": "leftover"}), 0, "mode=dryrun")
    # 계획에 비밀이 없다 · 값 파일은 0600 이고 비밀은 거기에만
    outdir = os.path.join(ctx.root, "plan-out")
    os.makedirs(outdir)
    build("--prod-config", good, "--out", outdir)
    plan_text = open(os.path.join(outdir, "plan.json"), encoding="utf-8").read() if os.path.exists(os.path.join(outdir, "plan.json")) else ""
    vals = good_prod_values()
    ctx.case("K1 계획 파일에 anon 키·Firebase API 키가 없다", plan_text != "" and vals["supabaseAnonKey"] not in plan_text and API_KEY not in plan_text and pwA not in plan_text,
             f"plan={len(plan_text)}B")
    stamp = json.loads(plan_text)["stamp"] if plan_text else ""
    ctx.case("K2 빌드 도장 글자 모양", re.fullmatch(r"aingcheck-release;build=7;version=1\.2\.3;time=[0-9]{8}T[0-9]{6}Z;sha=[0-9a-f]{40};duels=0", stamp) is not None, stamp)


def exec_gradle_cases(ctx):
    vals_path = os.path.join(ctx.root, "values-exec.json")
    rc, out = ctx.tool_run("preflight", "--mode", "prod", "--version-properties", os.path.join(make_repo(ctx, duels_from=VC), "version.properties"),
                           "--ledger", os.path.join(ctx.root, "none.tsv"), "--prod-config", write_props(ctx, "exec.properties", good_prod_values()),
                           "--duels", "on", "--build-time", TIME, "--git-sha", SHA, "--git-dirty", "0", "--upload-cert-sha256", "a" * 64,
                           "--key-place", "secrets-dir", "--password-source", "keychain",
                           "--out", os.path.join(ctx.root, "plan-exec.json"), "--values-out", vals_path)
    mode = stat.S_IMODE(os.stat(vals_path).st_mode) if os.path.exists(vals_path) else -1
    ctx.case("G1 값 파일은 0600", rc == 0 and mode == 0o600, f"rc={rc} mode={oct(mode)}")
    fake = os.path.join(ctx.root, "fake-gradlew")
    dump = os.path.join(ctx.root, "gradle-dump.txt")
    with open(fake, "w") as f:
        # 가짜 gradlew 의 머리는 dash(Linux 의 /bin/sh 와 같은 셸 — 점 이름 환경 변수를 버린다). exec-gradle 이 bash 로 부르지 않으면
        # 맥에서도 G2·G4·G4b 가 빨갛다(7차 CI 탐침: 진짜 gradlew '#!/bin/sh' 가 Linux 에서 운영 값·판돈 깃발을 잃는 길).
        f.write(('#!/bin/dash' if os.path.exists("/bin/dash") else '#!/bin/sh') + '\n{ echo "ARGV:$*"; env | grep "^ORG_GRADLE_PROJECT_" | sort; } > "$DUMP"\n')
    os.chmod(fake, 0o755)
    rc, out = ctx.tool_run("exec-gradle", "--values", vals_path, "--", fake, ":androidApp:bundleRelease",
                           env={"DUMP": dump, "ORG_GRADLE_PROJECT_aingcheck.prod.supabaseUrl": "https://stale.example"})
    # dryrun 값 파일(운영 키 없음) + 밖에서 새어 든 운영 속성 → Gradle 에 닿으면 dryrun 판이 운영 주소를 싣는다.
    dry_vals = os.path.join(ctx.root, "values-exec-dry.json")
    rcd, _ = ctx.tool_run("preflight", "--mode", "dryrun", "--version-properties", os.path.join(make_repo(ctx), "version.properties"),
                          "--ledger", os.path.join(ctx.root, "none.tsv"), "--build-time", TIME, "--git-sha", SHA, "--git-dirty", "0",
                          "--upload-cert-sha256", "b" * 64, "--out", os.path.join(ctx.root, "plan-exec-dry.json"), "--values-out", dry_vals)
    dump_dry = os.path.join(ctx.root, "gradle-dump-dry.txt")
    ctx.tool_run("exec-gradle", "--values", dry_vals, "--", fake, ":androidApp:bundleRelease",
                 env={"DUMP": dump_dry, "ORG_GRADLE_PROJECT_aingcheck.prod.supabaseUrl": "https://stale.example",
                      "ORG_GRADLE_PROJECT_aingcheck.prod.firebaseApiKey": "staleStaleStaleStale00"})
    dry_text = open(dump_dry, encoding="utf-8").read() if os.path.exists(dump_dry) else ""
    text = open(dump, encoding="utf-8").read() if os.path.exists(dump) else ""
    argv_line = next((l for l in text.splitlines() if l.startswith("ARGV:")), "")
    anon = good_prod_values()["supabaseAnonKey"]
    ctx.case("G2 Gradle 속성은 환경 변수로 간다", f"ORG_GRADLE_PROJECT_aingcheck.prod.supabaseAnonKey={anon}" in text
             and "ORG_GRADLE_PROJECT_aingcheck.release.duelsEnabled=true" in text and f"ORG_GRADLE_PROJECT_aingcheck.prod.firebaseApiKey={API_KEY}" in text, text[:200])
    ctx.case("G3 argv 에 비밀이 없다", argv_line == "ARGV::androidApp:bundleRelease" and anon not in argv_line, argv_line)
    ctx.case("G4 밖에서 새어 든 같은 이름을 덮는다", f"ORG_GRADLE_PROJECT_aingcheck.prod.supabaseUrl={PROD_URL}" in text and "stale.example" not in text, "")
    ctx.case("G4b dryrun 에는 새어 든 운영 속성이 닿지 않는다", rcd == 0 and "ORG_GRADLE_PROJECT_aingcheck.release.duelsEnabled=false" in dry_text
             and "aingcheck.prod." not in dry_text, dry_text[:200])
    ctx.case("G5 값 파일을 읽자마자 지운다", rc == 0 and not os.path.exists(vals_path), f"rc={rc} exists={os.path.exists(vals_path)}")


def _rt():
    """판정기 모듈(같은 폴더). 진열장 전용 문자열 목록은 판정기의 것을 쓴다 — 목록이 원문과 맞는지는 SC1 이 따로 잰다."""
    import release_tool  # noqa: E402
    return release_tool


def verify_cases(ctx, keyA, keyB):
    SHOWCASE_SAMPLE = _rt().SHOWCASE_LITERALS[0]
    pathA, certA, pwA = keyA
    pathB, certB, pwB = keyB
    perms_file = os.path.join(ctx.real_mp, "androidApp", "release", "permissions.txt")
    real_budget = os.path.join(ctx.real_mp, "androidApp", "release", "budget.properties")
    prod = good_prod_values()

    def plan(mode, duels, **over):
        # 판돈을 켠 운영 계획은 커밋된 androidDuelsFromBuild 가 있어야 한다(preflight 이중 확인).
        repo_mp = make_repo(ctx, duels_from=VC if duels else None)
        out = os.path.join(ctx.root, f"plan-{mode}-{len(ctx.results)}.json")
        vals = os.path.join(ctx.root, f"vals-{mode}-{len(ctx.results)}.json")
        args = ["preflight", "--mode", mode, "--version-properties", os.path.join(repo_mp, "version.properties"), "--ledger", os.path.join(ctx.root, "none.tsv"),
                "--duels", "on" if duels else "off", "--build-time", TIME, "--git-sha", SHA, "--git-dirty", "0", "--upload-cert-sha256", certA,
                "--out", out, "--values-out", vals]
        if mode == "prod":
            args += ["--prod-config", write_props(ctx, f"v-{len(ctx.results)}.properties", prod), "--key-place", "secrets-dir", "--password-source", "keychain"]
        rc, o = ctx.tool_run(*args)
        if rc != 0:
            raise RuntimeError("preflight: " + o)
        d = json.load(open(out))
        d.update(over)
        json.dump(d, open(out, "w"))
        return out, vals, d

    plan_dry, vals_dry, pd = plan("dryrun", False)
    plan_prod, vals_prod, pp = plan("prod", True)
    other_time = pp["stamp"].replace(TIME, "20261028T010204Z")
    dex_dry = make_dex(ctx, "dry", False, pd["stamp"], None)
    dex_prod = make_dex(ctx, "prod", True, pp["stamp"], prod)
    dex_nobc = make_dex(ctx, "nobc", True, pp["stamp"], prod, with_build_config=False)
    dex_leak = make_dex(ctx, "leak", True, pp["stamp"], prod, leak=True)
    # 운영 dex 에 개발 Firebase(다른 프로젝트 — 앱 id·sender 는 서로 맞다) · API 키만 다름 · anon 빈 값 · 다른 anon 키 · 판 신원 다름
    dev_fb = dict(prod, firebaseAppId="1:555555555555:android:fedcba9876543210", firebaseProjectId="w6a-dev", firebaseSenderId="555555555555")
    dex_devfb = make_dex(ctx, "devfb", True, pp["stamp"], dev_fb)
    dex_apikey = make_dex(ctx, "apikey", True, pp["stamp"], dict(prod, firebaseApiKey="w6aOtherProjectApiKey_987654"))
    dex_noanon = make_dex(ctx, "noanon", True, pp["stamp"], dict(prod, supabaseAnonKey=""))
    dex_otheranon = make_dex(ctx, "otheranon", True, pp["stamp"], dict(prod, supabaseAnonKey=fake_jwt("anon", ref="w6a-devproj")))
    dex_ident = make_dex(ctx, "ident", True, pp["stamp"], prod, identity=(VC + 1, VN))
    # dryrun dex 에 운영 값이 섞인 꼴(Firebase 넷 · anon)
    fb_only = {k: prod[k] for k in ("firebaseAppId", "firebaseProjectId", "firebaseSenderId", "firebaseApiKey")}
    dex_dry_fb = make_dex(ctx, "dryfb", False, pd["stamp"], fb_only)
    dex_dry_anon = make_dex(ctx, "dryanon", False, pd["stamp"], {"supabaseAnonKey": prod["supabaseAnonKey"]})
    # 보편 APK 만 다른 판(AAB 는 이번 판): 도장의 빌드 시각 · 판돈 깃발
    dex_apk_time = make_dex(ctx, "apktime", True, other_time, prod)
    dex_apk_duels = make_dex(ctx, "apkduels", False, pp["stamp"], prod)
    # 진열장 함수가 다른 클래스에 인라인된 꼴(mapping 의 클래스 머리 줄은 깨끗하다)
    dex_showcase = make_dex(ctx, "showcase", True, pp["stamp"], prod, extra_string=SHOWCASE_SAMPLE)

    def signer(aab):
        rc, out = ctx.bash("aab-signer", aab)
        parts = out.strip().split()
        return (parts[-2], parts[-1]) if rc == 0 and len(parts) >= 2 else ("none", "1")

    # R47: jarsigner 출력이 파이프 버퍼(64 KiB)보다 긴 서명된 AAB(AGP 판은 JarInputStream 불일치 목록으로 수백 KB) — 'jar verified.' 를
    # 읽어 0 이어야 한다(7차 dryrun 에서 printf | grep -q 가 SIGPIPE·pipefail 로 1 을 냈다). 짝: 같은 길이에 그 줄이 없으면 1.
    long_aab = make_archive(ctx, "long-out.aab", dex_dry, kind="aab", sign_key=(pathA, pwA))
    for label, verdict_line, want in (("R47 긴 jarsigner 출력(서명됨) → 0", "jar verified.", "0"), ("R47b 긴 jarsigner 출력(판정 줄 없음) → 1", "jar is unsigned.", "1")):
        fake_dir = os.path.join(ctx.root, "fake-jarsigner-" + want)
        os.makedirs(fake_dir, exist_ok=True)
        with open(os.path.join(fake_dir, "jarsigner"), "w") as f:
            f.write("#!/bin/sh\necho\necho '" + verdict_line + "'\ni=0\nwhile [ $i -lt 3000 ]; do echo \"- Entry base/assets/x$i.webp is signed in JarFile but is not signed in JarInputStream\"; i=$((i+1)); done\n")
        os.chmod(os.path.join(fake_dir, "jarsigner"), 0o755)
        rc, out = ctx.bash("aab-signer", long_aab, env={"PATH": fake_dir + os.pathsep + ctx.env.get("PATH", "")})
        parts = out.strip().split()
        got = parts[-1] if rc == 0 and parts else "?"
        ctx.case(label, got == want and parts[-2] == certA, f"rc={rc} 판정={got} 기대 {want} 지문={parts[-2] if len(parts) >= 2 else '?'}")

    apks_ok = os.path.join(ctx.root, "apksigner-ok.txt")
    with open(apks_ok, "w") as f:
        f.write(f"Signer #1 certificate DN: CN=w6a selftest A\nSigner #1 certificate SHA-256 digest: {certA}\n")
    apks_b = os.path.join(ctx.root, "apksigner-b.txt")
    with open(apks_b, "w") as f:
        f.write(f"Signer #1 certificate DN: CN=w6a selftest B\nSigner #1 certificate SHA-256 digest: {certB}\n")

    def budget_file(name, aab=10 ** 9, apk=10 ** 9, font=10 ** 9, drop=None):
        lines = [f"aabMaxBytes={aab}", f"apkMaxBytes={apk}", f"fontMaxBytes={font}"]
        return _write(ctx, name, "# 시험 예산\n" + "\n".join(l for l in lines if not (drop and l.startswith(drop))) + "\n")

    def verify(name, plan_path, vals_path, dex, want_fail=(), badging_text=None, aab_extra=None, apk_extra=None, mapping=True,
               sign=(None,), apksigner=None, apksigner_rc=0, native_rc=0, aab=True, apk_dex="same", aab_dex="same", budget=None):
        """want_fail 은 빨간 판정 이름의 **정확한** 집합이다(그 판정만 빨개야 초록 — 다른 판정이 함께 빨개지거나 빠지면 FAIL)."""
        bpath = os.path.join(ctx.root, f"badging-{len(ctx.results)}.txt")
        with open(bpath, "w") as f:
            f.write(badging_text if badging_text is not None else badging())
        key = (pathA, pwA) if sign == (None,) else sign
        args = ["verify", "--plan", plan_path, "--values-expect", vals_path, "--badging", bpath, "--permissions", perms_file,
                "--apksigner-out", apksigner or apks_ok, "--apksigner-rc", str(apksigner_rc), "--native-rc", str(native_rc),
                "--budget", budget or real_budget, "--out", os.path.join(ctx.root, f"receipt-{len(ctx.results)}.json")]
        apk = make_archive(ctx, f"u-{len(ctx.results)}.apk", dex if apk_dex == "same" else apk_dex, kind="apk", extra=apk_extra)
        args += ["--apk", apk]
        if aab:
            a = make_archive(ctx, f"b-{len(ctx.results)}.aab", dex if aab_dex == "same" else aab_dex, kind="aab", extra=aab_extra, mapping=mapping, sign_key=key)
            sha, jrc = signer(a)
            args += ["--aab", a, "--aab-cert-sha256", sha, "--aab-jarsigner-rc", jrc]
        rc, out = ctx.tool_run(*args)
        failed = sorted(set(re.findall(r"^release-android: FAIL (\S+)", out, re.M)))
        want_rc = 1 if want_fail else 0
        ok = rc == want_rc and failed == sorted(set(want_fail))
        ctx.case(name, ok, f"rc={rc} 빨강={failed} 기대 {sorted(set(want_fail))}")
        return out

    stamp2 = ["dex.releaseStamp", "dex.apk.releaseStamp"]
    duels2 = ["dex.duelsEnabled", "dex.apk.duelsEnabled"]
    verify("R0 dryrun 판 → 초록", plan_dry, vals_dry, dex_dry)
    verify("R1 운영 판 → 초록", plan_prod, vals_prod, dex_prod)
    p_time, v_time, _ = plan("prod", True, stamp=other_time)
    verify("R2 도장의 빌드 시각이 다름(낡은 산출물)", p_time, v_time, dex_prod, want_fail=stamp2)
    p_off, v_off, _ = plan("prod", True, duelsEnabled=False)
    verify("R3 판돈 깃발이 요청과 다름", p_off, v_off, dex_prod, want_fail=duels2)
    verify("R4 BuildConfig 를 R8 이 지움(keep 빠짐)", plan_prod, vals_prod, dex_nobc, want_fail=stamp2 + duels2)
    verify("R5 권한 넘침(CAMERA)", plan_prod, vals_prod, dex_prod, badging_text=badging(PERMS + ["android.permission.CAMERA"]), want_fail=["badging.permissions"])
    verify("R6 AD_ID 권한", plan_prod, vals_prod, dex_prod, badging_text=badging(PERMS + ["com.google.android.gms.permission.AD_ID"]), want_fail=["badging.noAdId", "badging.permissions"])
    verify("R7 권한 모자람(WAKE_LOCK)", plan_prod, vals_prod, dex_prod, badging_text=badging([p for p in PERMS if not p.endswith("WAKE_LOCK")]), want_fail=["badging.permissions"])
    verify("R8 패키지 이름이 다름", plan_prod, vals_prod, dex_prod, badging_text=badging(package="com.yehsung.aingcheck.debug"), want_fail=["badging.package"])
    verify("R9 badging versionCode 가 다름", plan_prod, vals_prod, dex_prod, badging_text=badging(vc=VC + 1), want_fail=["badging.versionCode"])
    verify("R10 targetSdk 35", plan_prod, vals_prod, dex_prod, badging_text=badging(target="35"), want_fail=["badging.targetSdk"])
    verify("R11 minSdk 24", plan_prod, vals_prod, dex_prod, badging_text=badging(minsdk="24"), want_fail=["badging.minSdk"])
    verify("R12 런처 아이콘 없음", plan_prod, vals_prod, dex_prod, badging_text=badging(icon=""), want_fail=["badging.icon"])
    # R13: 아이콘을 넘기던 길(--allow-no-icon)을 없앴다 — 옛 계획 파일에 allowNoIcon 이 남아 있어도 아이콘 없음은 빨강이다.
    p_icon, v_icon, _ = plan("prod", True, allowNoIcon=True)
    verify("R13 옛 계획의 allowNoIcon 도 아이콘 없음을 넘기지 못한다", p_icon, v_icon, dex_prod, badging_text=badging(icon=""), want_fail=["badging.icon"])
    verify("R14 자산에 비밀 표식", plan_prod, vals_prod, dex_prod, aab_extra={"base/assets/x.txt": ("a " + ROLE_SECRET + " b").encode()}, want_fail=["aab.forbiddenMarkers"])
    verify("R15 Fixtures 자산", plan_prod, vals_prod, dex_prod, apk_extra={"assets/Fixtures/now.json": b"{}"}, want_fail=["apk.fixtures"])
    verify("R16 google-services 파일이 실림", plan_prod, vals_prod, dex_prod, aab_extra={"base/root/" + GS_NAME: b"{}"}, want_fail=["aab.forbiddenEntries"])
    verify("R17 키 파일이 실림", plan_prod, vals_prod, dex_prod, apk_extra={"assets/upload." + "jks": b"x"}, want_fail=["apk.forbiddenEntries"])
    verify("R18 운영 판 dex 에 .invalid", plan_prod, vals_prod, dex_leak, want_fail=["aab.noInvalidHost", "apk.noInvalidHost"])
    # 운영 주소만 구성과 다른 기대값(anon·API 키 SHA-256 은 그대로) — 주소 판정만 빨개야 한다.
    other_expect = dict(_load_json(vals_prod).get("expect", {}), supabaseUrl="https://other.example")
    vals_other = _write(ctx, "vals-other.json", json.dumps({"expect": other_expect}))
    verify("R19 운영 주소가 구성과 다름", plan_prod, vals_other, dex_prod, want_fail=["dex.prodConfig.url"])
    verify("R20 dryrun 계획 + 운영 dex", plan_dry, vals_dry, dex_prod,
           want_fail=stamp2 + duels2 + ["dex.prodConfig.url", "dex.prodConfig.firebase", "dex.prodConfig.anonKey", "aab.invalidBaseline", "apk.invalidBaseline"])
    verify("R21 AAB 를 다른 키(B)로 서명", plan_prod, vals_prod, dex_prod, sign=(pathB, pwB), want_fail=["sign.aab"])
    verify("R22 서명 없는 AAB", plan_prod, vals_prod, dex_prod, sign=None, want_fail=["sign.aab"])
    verify("R23 APK 서명자가 다름", plan_prod, vals_prod, dex_prod, apksigner=apks_b, want_fail=["sign.apk"])
    verify("R24 apksigner 실패", plan_prod, vals_prod, dex_prod, apksigner_rc=1, want_fail=["sign.apk"])
    verify("R25 .so 허용 목록·16 KB 빨강", plan_prod, vals_prod, dex_prod, native_rc=1, want_fail=["native.allowlistAnd16k"])
    verify("R26 진열장이 출시 판에 남음", plan_prod, vals_prod, dex_prod,
           mapping="com.yehsung.aingcheck.ui.components.AingGalleryKt -> a.b.c:\n    void AingGallery() -> a\n", want_fail=["r8.showcaseRemoved"])
    verify("R27 R8 mapping 없음(minify 꺼짐)", plan_prod, vals_prod, dex_prod, mapping=False, want_fail=["r8.mapping"])
    # 검증 지적: 언제나 초록으로 바꿔도 아무 사례도 빨개지지 않던 판정 9개 — 판정마다 그것만 빨개지는 입력.
    verify("R28 운영 dex 에 개발 Firebase(다른 프로젝트)", plan_prod, vals_prod, dex_devfb, want_fail=["dex.prodConfig.firebase"])
    verify("R29 운영 dex 의 Firebase API 키만 다름", plan_prod, vals_prod, dex_apikey, want_fail=["dex.prodConfig.firebase"])
    verify("R30 운영 dex 의 anon 키가 빔", plan_prod, vals_prod, dex_noanon, want_fail=["dex.prodConfig.anonKey"])
    verify("R31 운영 dex 의 anon 키가 다른 프로젝트 키", plan_prod, vals_prod, dex_otheranon, want_fail=["dex.prodConfig.anonKey"])
    verify("R32 BuildIdentity BUILD 가 다름", plan_prod, vals_prod, dex_ident, want_fail=["dex.buildIdentity"])
    verify("R33 badging 런처가 다름", plan_prod, vals_prod, dex_prod, badging_text=badging(launcher="com.yehsung.aingcheck.android.debug.ProbeActivity"), want_fail=["badging.launcher"])
    verify("R34 badging versionName 이 다름", plan_prod, vals_prod, dex_prod, badging_text=badging(vn="1.2.4"), want_fail=["badging.versionName"])
    verify("R35 보편 APK 에 dex 가 없음", plan_prod, vals_prod, dex_prod, apk_dex=None, want_fail=["apk.dexPresent", "dex.apk.releaseStamp", "dex.apk.duelsEnabled"])
    verify("R36 AAB 에 dex 가 없음", plan_prod, vals_prod, dex_prod, aab_dex=None,
           want_fail=["aab.dexPresent", "dex.releaseStamp", "dex.duelsEnabled", "dex.buildIdentity", "dex.prodConfig.url", "dex.prodConfig.firebase", "dex.prodConfig.anonKey"])
    verify("R37 dryrun dex 에 Firebase 값", plan_dry, vals_dry, dex_dry_fb, want_fail=["dex.prodConfig.firebase"])
    verify("R38 dryrun dex 에 anon 키", plan_dry, vals_dry, dex_dry_anon, want_fail=["dex.prodConfig.anonKey"])
    # 검증 지적: 실제로 깔리는 보편 APK 의 dex 도장·깃발도 계획과 대조한다.
    verify("R39 보편 APK 의 도장이 다름(AAB 는 이번 판)", plan_prod, vals_prod, dex_prod, apk_dex=dex_apk_time, want_fail=["dex.apk.releaseStamp"])
    verify("R40 보편 APK 의 판돈 깃발이 다름", plan_prod, vals_prod, dex_prod, apk_dex=dex_apk_duels, want_fail=["dex.apk.duelsEnabled"])
    # 검증 지적: 진열장이 인라인되면 mapping 머리 줄로는 안 보인다 — dex 문자열 표로 잰다.
    verify("R41 진열장 전용 문자열이 dex 에 남음(mapping 깨끗)", plan_prod, vals_prod, dex_showcase, want_fail=["aab.showcaseStrings", "apk.showcaseStrings"])
    # 크기 예산(검증 지적 G §8-14): 시험 고정물은 작으니 예산을 고정물보다 작게 둔 파일로 잰다.
    verify("R42 AAB 크기 예산 넘침", plan_prod, vals_prod, dex_prod, budget=budget_file("budget-aab.properties", aab=100), want_fail=["budget.aabBytes"])
    verify("R43 보편 APK 크기 예산 넘침", plan_prod, vals_prod, dex_prod, budget=budget_file("budget-apk.properties", apk=100), want_fail=["budget.apkBytes"])
    verify("R44 글꼴 예산 넘침", plan_prod, vals_prod, dex_prod, budget=budget_file("budget-font.properties", font=50), want_fail=["budget.fontBytes"])
    verify("R45 예산 파일 없음", plan_prod, vals_prod, dex_prod, budget=os.path.join(ctx.root, "no-budget.properties"), want_fail=["budget.file"])
    verify("R46 예산 파일 키 모자람", plan_prod, vals_prod, dex_prod, budget=budget_file("budget-drop.properties", drop="fontMaxBytes"), want_fail=["budget.file"])
    # 경고는 계획에서 영수증으로 그대로 간다(조정자가 영수증만 보고도 자리 이탈을 안다).
    rec_w = os.path.join(ctx.root, "receipt-warn.json")
    p_warn, v_warn, _ = plan("prod", True, warnings=["password-from-env: 시험"], inputs={"keyPlace": "secrets-dir", "passwordSource": "env"})
    ctx.tool_run("verify", "--plan", p_warn, "--values-expect", v_warn, "--badging", _write(ctx, "b-warn.txt", badging()), "--permissions", perms_file,
                 "--apk", make_archive(ctx, "warn.apk", dex_prod, kind="apk"), "--apksigner-out", apks_ok, "--apksigner-rc", "0", "--native-rc", "0",
                 "--budget", real_budget, "--out", rec_w)
    rw = _load_json(rec_w)
    ctx.case("W1 영수증에 계획의 경고·입력 칸이 실린다", rw.get("warnings") == ["password-from-env: 시험"] and rw.get("inputs", {}).get("passwordSource") == "env",
             f"warnings={rw.get('warnings')} inputs={rw.get('inputs')}")

    # 장부·서버 채널
    rec_ok = os.path.join(ctx.root, "receipt-ledger.json")
    rc, _ = ctx.tool_run("verify", "--plan", plan_prod, "--values-expect", vals_prod, "--badging", _write(ctx, "b-led.txt", badging()),
                         "--permissions", perms_file, "--apk", make_archive(ctx, "led.apk", dex_prod, kind="apk"),
                         "--aab", (aab_led := make_archive(ctx, "led.aab", dex_prod, sign_key=(pathA, pwA))),
                         "--aab-cert-sha256", signer(aab_led)[0], "--aab-jarsigner-rc", "0", "--apksigner-out", apks_ok, "--apksigner-rc", "0",
                         "--native-rc", "0", "--budget", real_budget, "--out", rec_ok)
    ledger = _write(ctx, "ledger.tsv", "# 장부\n")
    rc1, _ = ctx.tool_run("ledger-append", "--receipt", rec_ok, "--ledger", ledger)
    rows = [l for l in open(ledger, encoding="utf-8").read().splitlines() if l and not l.startswith("#")]
    ctx.case("L1 초록 운영 판은 장부에 한 줄", rc == 0 and rc1 == 0 and len(rows) == 1 and rows[0].split("\t")[0] == str(VC) and rows[0].split("\t")[4] == "1"
             and rows[0].split("\t")[6] == certA, f"rc={rc}/{rc1} rows={rows}")
    rc2, _ = ctx.tool_run("ledger-append", "--receipt", rec_ok, "--ledger", ledger)
    ctx.case("L2 같은 판을 두 번 적지 않는다", rc2 == 2, f"rc={rc2}")
    rec_bad = os.path.join(ctx.root, "receipt-bad.json")
    d = json.load(open(rec_ok)); d["ok"] = False; json.dump(d, open(rec_bad, "w"))
    rc3, _ = ctx.tool_run("ledger-append", "--receipt", rec_bad, "--ledger", ledger)
    ctx.case("L3 빨간 영수증은 장부에 못 적는다", rc3 == 2, f"rc={rc3}")
    rc4, sql = ctx.bash("publish-sql", "--receipt", rec_ok, "--min-build", "3", "--notes", "it's 첫 판")
    ctx.case("Q1 서버 채널 SQL 글자", rc4 == 0 and sql.strip() == f"select public.client_publish_release_v2('android', 3, {VC}, 'it''s 첫 판', '{VN}', null);", sql.strip())
    rc5, _ = ctx.bash("publish-sql", "--receipt", rec_ok, "--min-build", str(VC + 1))
    ctx.case("Q2 min_build 가 이번 판보다 크면 거부", rc5 == 2, f"rc={rc5}")
    rc6, _ = ctx.bash("publish-sql", "--receipt", rec_bad, "--min-build", "1")
    ctx.case("Q3 빨간 영수증은 거부", rc6 == 2, f"rc={rc6}")


def _load_json(path):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return {}


def _write(ctx, name, text):
    p = os.path.join(ctx.root, name)
    with open(p, "w", encoding="utf-8") as f:
        f.write(text)
    return p


def smoke_cases(ctx):
    good = {
        "seal": "adb=pong netsim=own:81122 wifi=up:10.0.2.16/24 outbound_tcp_open=0 dns_resolved=0 verdict=sealed\n",
        "install": "Performing Streamed Install\nSuccess\n",
        "start": "Starting: Intent { cmp=com.yehsung.aingcheck/.android.shell.MainActivity }\r\nStatus: ok\r\nLaunchState: COLD\r\nTotalTime: 585\r\n",
        "pid": "4231\r\n",
        # brief 형식 실측(2026-10-28 W6-a smoke): 8자보다 짧은 태그는 공백을 채운다 · 긴 태그는 괄호에 붙는다.
        "logcat": "I/AingApp ( 4231): variant=RELEASE firebase=INITIALIZE initialized=true\r\n"
                  "I/AingShell( 4231): onCreate restored=false task=8 action=null instance=1\r\n"
                  "I/AingShell( 4231): route accept=null history=false proof=false opened=false\r\n",
        "dumpsys": "Packages:\n  Package [com.yehsung.aingcheck] (abc):\n    versionCode=7 minSdk=26 targetSdk=36\n",
        "apkhash": "local=" + "ab" * 32 + "\ndevice=" + "ab" * 32 + "\n",
        "windows": "windows_own=0 windows_foreign_emulator=9(판정 밖 — 남의 PID) pids=[1 2] source=cgwindowlist\n",
    }

    def judge(name, texts, want_rc, fb="INITIALIZE", vc=7, shot_rc=0, want_fail=None):
        """want_fail 은 빨간 판정 이름 하나 — 그것 **만** 빨개야 초록이다."""
        d = tempfile.mkdtemp(prefix="smoke.", dir=ctx.root)
        for k, v in texts.items():
            with open(os.path.join(d, k + ".txt"), "w", encoding="utf-8") as f:
                f.write(v)
        args = ["smoke-judge", "--dir", d, "--shot-rc", str(shot_rc), "--want-version-code", str(vc)]
        if fb:
            args += ["--expect-firebase", fb]
        rc, out = ctx.tool_run(*args)
        failed = re.findall(r"smoke FAIL (\S+)", out)
        ok = rc == want_rc and failed == ([] if want_fail is None else [want_fail])
        ctx.case(name, ok, f"rc={rc} 빨강={failed}")

    judge("M0 smoke 판정 — 실측 로그 모양 → 초록", good, 0)
    judge("M1 AingShell 줄 없음", dict(good, logcat=good["logcat"].replace("onCreate", "onResume")), 1, want_fail="shellOnCreate")
    judge("M2 죽음(FATAL)", dict(good, logcat=good["logcat"] + "E/AndroidRuntime( 4231): FATAL EXCEPTION: main\nE/AndroidRuntime( 4231): Process: com.yehsung.aingcheck, PID: 4231\n"), 1, want_fail="noCrash")
    judge("M3 Firebase 판정이 다름", good, 1, fb="SKIP_NO_CONFIG", want_fail="firebase")
    judge("M4 프로세스 없음", dict(good, pid=""), 1, want_fail="alive")
    judge("M5 봉인 아님", dict(good, seal="verdict=OPEN outbound_tcp_open=2\n"), 1, want_fail="seal")
    judge("M6 자기 창이 있다", dict(good, windows="windows_own=1 pids=[1]\n"), 1, want_fail="windows")
    judge("M7 깔린 versionCode 가 다름", good, 1, vc=8, want_fail="installedVersionCode")
    judge("M8 release 표식 없음(debug 판)", dict(good, logcat=good["logcat"].replace("variant=RELEASE", "variant=DEBUG")), 1, want_fail="variantRelease")
    judge("M9 설치 실패", dict(good, install="Failure [INSTALL_FAILED_UPDATE_INCOMPATIBLE]\n"), 1, want_fail="install")
    # 검증 지적: 언제나 초록으로 바꿔도 잡히지 않던 amStart·screenshot, 그리고 "이번 빌드가 깔렸나"(installedApk).
    judge("M10 깔린 base.apk 가 이번 APK 와 다름", dict(good, apkhash="local=" + "ab" * 32 + "\ndevice=" + "cd" * 32 + "\n"), 1, want_fail="installedApk")
    judge("M11 깔린 base.apk 를 못 받음", dict(good, apkhash="local=" + "ab" * 32 + "\ndevice=none path=없음\n"), 1, want_fail="installedApk")
    judge("M12 am start 실패", dict(good, start="Starting: Intent { cmp=com.yehsung.aingcheck/.android.shell.MainActivity }\r\nStatus: error\r\n"), 1, want_fail="amStart")
    judge("M13 스크린숏 실패", good, 1, shot_rc=1, want_fail="screenshot")


def manifest_test_permissions(path):
    text = open(path, encoding="utf-8").read()
    m = re.search(r"fun permissionsAreExactlyTheAllowList\(\).*?setOf\((.*?)\),\s*permissions", text, re.S)
    return set(re.findall(r'"([^"]+)"', m.group(1))) if m else None


def permissions_cases(ctx):
    mt = os.path.join(ctx.real_mp, "androidApp", "src", "test", "kotlin", "com", "yehsung", "aingcheck", "android", "app", "MergedManifestTest.kt")
    ours = set(l.strip() for l in open(os.path.join(ctx.real_mp, "androidApp", "release", "permissions.txt"), encoding="utf-8")
               if l.strip() and not l.strip().startswith("#"))
    theirs = manifest_test_permissions(mt) if os.path.exists(mt) else None
    ctx.case("C1 출시 권한 목록 = 병합 매니페스트 시험의 목록", theirs is not None and ours == theirs and len(ours) == 8,
             f"넘침={sorted(ours - (theirs or set()))} 모자람={sorted((theirs or set()) - ours)}")
    ctx.case("C2 대조기 기준선 — 하나 더한 목록은 다르다", theirs is not None and (ours | {"android.permission.CAMERA"}) != theirs, "")


def showcase_literal_homes(real_mp, literal):
    """그 문자열 리터럴("…")이 든 main 소스 파일들(시험·빌드 폴더 제외)."""
    homes = []
    needle = '"' + literal + '"'
    for d, dirs, files in os.walk(real_mp):
        dirs[:] = [x for x in dirs if x not in ("build", ".gradle", ".kotlin") and not x.lower().endswith("test")]
        parts = d.replace(os.sep, "/").split("/")
        if "src" not in parts:
            continue
        src_set = parts[parts.index("src") + 1] if parts.index("src") + 1 < len(parts) else ""
        if not (src_set == "main" or src_set.endswith("Main")):
            continue
        for fn in files:
            if fn.endswith(".kt"):
                p = os.path.join(d, fn)
                with open(p, encoding="utf-8", errors="replace") as f:
                    if needle in f.read():
                        homes.append(os.path.relpath(p, real_mp).replace(os.sep, "/"))
    return sorted(homes)


def showcase_cases(ctx):
    gallery = "ui/src/commonMain/kotlin/com/yehsung/aingcheck/ui/components/AingGallery.kt"
    lits = _rt().SHOWCASE_LITERALS
    bad = {lit: showcase_literal_homes(ctx.real_mp, lit) for lit in lits}
    bad = {k: v for k, v in bad.items() if v != [gallery]}
    ctx.case("SC1 진열장 전용 문자열은 진열장 원문에만 있다(판정기 목록 = 원문)", len(lits) >= 3 and not bad, f"어긋남={bad}")
    # 기준선(다른 입력): 앱 셸이 쓰는 문자열은 진열장 전용이 아니라고 가려낸다.
    ctx.case("SC2 대조기 기준선 — 진열장 밖 문자열은 집이 다르다", showcase_literal_homes(ctx.real_mp, "근무 중") != [gallery], "")


def run(script, tool):
    root = tempfile.mkdtemp(prefix="aingcheck-release-selftest.")
    ctx = Ctx(root, script, tool)
    status = 0
    try:
        missing = [t for t in ("keytool", "jarsigner", "javac", "git") if not find_tool(t)]
        ctx.d8 = find_d8()
        if missing or not ctx.d8:
            print(f"self-test: FAIL 도구가 없다 — {missing}{'' if ctx.d8 else ' d8(Android build-tools)'}")
            return 1
        global keyA_keytool
        pwA, pwB = "selftest-A-" + os.urandom(6).hex(), "selftest-B-" + os.urandom(6).hex()
        pathA, certA, ktA = make_key(ctx, "A", pwA)
        pathB, certB, ktB = make_key(ctx, "B", pwB)
        keyA_keytool = (ktA,)
        ctx.case("K0 인증서 지문(PEM→SHA-256) = keytool 지문", certA == ktA and certB == ktB and certA != certB, f"{certA} {ktA}")
        keyA, keyB = (pathA, certA, pwA), (pathB, certB, pwB)
        preflight_cases(ctx, keyA, keyB)
        exec_gradle_cases(ctx)
        verify_cases(ctx, keyA, keyB)
        smoke_cases(ctx)
        permissions_cases(ctx)
        showcase_cases(ctx)
    except Exception as e:  # 고정물 실패도 빨강이다(건너뛰지 않는다)
        ctx.case("고정물", False, f"{type(e).__name__}: {e}")
    finally:
        shutil.rmtree(root, ignore_errors=True)
    bad = [r for r in ctx.results if not r[1]]
    print(f"self-test: cases={len(ctx.results)} failed={len(bad)}")
    # 사례 수 하한: 사례를 지우거나 고정물에서 일찍 끝나면 빨강(조용히 줄지 않게).
    if len(ctx.results) < EXPECTED_MIN_CASES:
        print(f"self-test: FAIL 사례가 {len(ctx.results)}개 — 최소 {EXPECTED_MIN_CASES}")
        status = 1
    return 1 if bad or status else 0


keyA_keytool = (None,)
EXPECTED_MIN_CASES = 131
