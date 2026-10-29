# 원본: 없음 — Android 출시 도구(W6-a · G §2-3 W6-a 행 · §4-1 · E§9.3·9.7·9.9·§11 · A§6-1). 표준 라이브러리만 쓴다(python3 -I).
#
# multiplatform/scripts/release-android.sh 가 부르는 판정 몫이다. 셸은 도구(Gradle·aapt2·keytool·apksigner)를 돌리고,
# 이 파일은 (1) 입력 판정(preflight) (2) 비밀을 argv 에 싣지 않는 Gradle 실행(exec-gradle) (3) 산출물 판정(verify)
# (4) 판 장부(ledger) (5) 서버 출시 채널 SQL 글자(publish-sql — 실행하지 않는다) (6) 자기 시험(self-test)을 한다.
#
# 원칙
#   - 운영 값(Supabase anon 키·Firebase 넷)과 업로드 키 비밀번호는 argv·계획 파일·영수증·로그에 싣지 않는다.
#     Gradle 속성은 환경 변수 ORG_GRADLE_PROJECT_aingcheck.prod.* 로 넘긴다(점이 든 이름이라 셸 export 로는 못 만든다 — execve 로 직접).
#   - 판정은 산출물에서 다시 읽은 값으로 한다: aapt2 dump badging(패키지·판 번호·SDK·권한) · dex 의 정적 필드 값
#     (BuildConfig.RELEASE_STAMP·DUELS_ENABLED · ProdConfig · BuildIdentity) · 서명 인증서 지문 · 압축 안 내용물.
#   - 거부는 종료 코드 2(입력이 틀렸다), 산출물 판정 실패는 1.
import argparse
import base64
import hashlib
import json
import os
import re
import stat
import struct
import sys
import zipfile

PACKAGE = "com.yehsung.aingcheck"
TARGET_SDK = "36"
MIN_SDK = "26"
LAUNCHER = "com.yehsung.aingcheck.android.shell.MainActivity"
BUILD_CONFIG = "Lcom/yehsung/aingcheck/android/BuildConfig;"
PROD_CONFIG = "Lcom/yehsung/aingcheck/android/generated/ProdConfig;"
BUILD_IDENTITY = "Lcom/yehsung/aingcheck/android/generated/BuildIdentity;"
INVALID_URL = "https://aingcheck.invalid"
# 서버 app_build 범위(K5 · client_publish_release_v2 의 1..1000000).
VERSION_CODE_MAX = 1_000_000
PROD_KEYS = ("supabaseUrl", "supabaseAnonKey", "firebaseAppId", "firebaseProjectId", "firebaseSenderId", "firebaseApiKey")
FIREBASE_KEYS = PROD_KEYS[2:]
# 표식 글자는 이어 붙여 만든다(저장소 푸시 전 비밀 검사가 글자 그대로 grep 한다). build-logic AingcheckBuild.kt 와 같은 목록 + 두 줄.
FORBIDDEN_MARKERS = [
    ("service" + "_role").encode(),
    ("sb" + "_secret_").encode(),
    ("BEGIN " + "PRIVATE KEY").encode(),
    ("BEGIN RSA " + "PRIVATE KEY").encode(),
    ("BEGIN EC " + "PRIVATE KEY").encode(),
    ("private" + "_key_id").encode(),  # 서비스 계정 JSON 의 칸 이름
]
# 산출물에 있으면 안 되는 파일 이름(끝 글자, 소문자 비교).
# 글자는 이어 붙인다(저장소 푸시 전 비밀 검사가 이 이름들을 글자 그대로 찾는다).
GS_JSON = "google-services" + ".json"
FORBIDDEN_ENTRY_SUFFIXES = (GS_JSON, "." + "jks", "." + "keystore", ".p12", ".pem", ".p8", "service-account" + ".json")
# 출시 판에서 빠져야 하는 클래스(진열장 — G §8-13·§8-14: release 제외는 W6-a). R8 이 지웠는지 mapping 으로 잰다.
SHOWCASE_PREFIXES = ("com.yehsung.aingcheck.ui.components.AingGallery",)
# exec-gradle 이 gradlew 를 부르는 셸(아래 cmd_exec_gradle — dash 는 점 이름 환경 변수를 버린다).
BASH = "/bin/bash"
# 진열장 **전용** 문자열 리터럴(ui/.../components/AingGallery.kt 에만 있다 — 자기 시험 SC1 이 원문에서 잰다). 진열장 함수가 다른 클래스에
# 인라인되면 mapping 의 클래스 머리 줄로는 안 보이므로, 산출물 dex 문자열 표에 이 글자가 0 인지 함께 잰다(검증 지적 r8.showcaseRemoved).
SHOWCASE_LITERALS = ("섹션 제목 20 bold", "행 이름 16 semibold · 부제 13", "3단 글자 label3Text — 끝난 할 일", "보조 글자 label2 — 오늘 3시간 12분 근무")
# 크기 예산 키(androidApp/release/budget.properties — 바이트). 넘으면 verify 빨강.
BUDGET_KEYS = ("aabMaxBytes", "apkMaxBytes", "fontMaxBytes")
# 업로드 키 기본 자리(G §2-3 W6-a 행). 다른 자리·환경 변수 비밀번호는 경고(영수증 warnings).
KEY_PLACES = ("secrets-dir", "other", "throwaway")
PASSWORD_SOURCES = ("keychain", "env", "throwaway")

FIREBASE_SHAPES = {
    "firebaseAppId": re.compile(r"^1:[0-9]{3,20}:android:[0-9a-f]{6,40}$"),
    "firebaseProjectId": re.compile(r"^[a-z][a-z0-9-]{4,28}[a-z0-9]$"),
    "firebaseSenderId": re.compile(r"^[0-9]{3,20}$"),
    "firebaseApiKey": re.compile(r"^[A-Za-z0-9_-]{20,80}$"),
}


class Refuse(Exception):
    """입력 거부(종료 코드 2)."""


# ============================================================================ dex 읽기(정적 필드 값)

def _uleb128(buf, off):
    result, shift = 0, 0
    while True:
        b = buf[off]
        off += 1
        result |= (b & 0x7F) << shift
        if b < 0x80:
            return result, off
        shift += 7


def _mutf8(raw):
    s = raw.replace(b"\xc0\x80", b"\x00").decode("utf-8", errors="surrogatepass")
    return s.encode("utf-16", "surrogatepass").decode("utf-16")


class Dex:
    """dex 한 벌에서 문자열·클래스·정적 필드 값을 읽는다(실행하지 않는다). 형식: source.android.com/docs/core/runtime/dex-format."""

    def __init__(self, data):
        if data[:4] != b"dex\n":
            raise ValueError("dex 가 아니다")
        self.data = data
        u = lambda o: struct.unpack_from("<I", data, o)[0]
        self.string_ids_size, self.string_ids_off = u(0x38), u(0x3C)
        self.type_ids_size, self.type_ids_off = u(0x40), u(0x44)
        self.field_ids_size, self.field_ids_off = u(0x50), u(0x54)
        self.class_defs_size, self.class_defs_off = u(0x60), u(0x64)

    def string(self, idx):
        off = struct.unpack_from("<I", self.data, self.string_ids_off + 4 * idx)[0]
        _, p = _uleb128(self.data, off)
        end = self.data.index(b"\x00", p)
        return _mutf8(self.data[p:end])

    def strings(self):
        return [self.string(i) for i in range(self.string_ids_size)]

    def type_name(self, idx):
        return self.string(struct.unpack_from("<I", self.data, self.type_ids_off + 4 * idx)[0])

    def field(self, idx):
        off = self.field_ids_off + 8 * idx
        class_idx, type_idx = struct.unpack_from("<HH", self.data, off)
        name_idx = struct.unpack_from("<I", self.data, off + 4)[0]
        return self.type_name(class_idx), self.type_name(type_idx), self.string(name_idx)

    def class_names(self):
        return [self.type_name(struct.unpack_from("<I", self.data, self.class_defs_off + 32 * i)[0]) for i in range(self.class_defs_size)]

    def _value(self, p):
        b = self.data[p]
        p += 1
        vtype, varg = b & 0x1F, b >> 5
        if vtype == 0x1F:
            return bool(varg), p
        if vtype == 0x1E:
            return None, p
        if vtype == 0x1C:
            return self._array(p)
        if vtype == 0x1D:
            _, p = _uleb128(self.data, p)
            n, p = _uleb128(self.data, p)
            for _ in range(n):
                _, p = _uleb128(self.data, p)
                _, p = self._value(p)
            return ("annotation",), p
        size = varg + 1
        raw = self.data[p:p + size]
        p += size
        if vtype == 0x17:
            return self.string(int.from_bytes(raw, "little")), p
        if vtype in (0x00, 0x02, 0x04, 0x06):
            return int.from_bytes(raw, "little", signed=True), p
        if vtype == 0x03:
            return int.from_bytes(raw, "little"), p
        return ("raw", vtype, raw.hex()), p

    def _array(self, p):
        n, p = _uleb128(self.data, p)
        out = []
        for _ in range(n):
            v, p = self._value(p)
            out.append(v)
        return out, p

    def static_fields(self, descriptor):
        """descriptor 클래스의 정적 필드 {이름: (형식, 값)}. 클래스가 없으면 None. 값 배열 뒤쪽이 빠졌으면 형식의 기본값(dex 규약)."""
        for i in range(self.class_defs_size):
            off = self.class_defs_off + 32 * i
            vals = struct.unpack_from("<8I", self.data, off)
            if self.type_name(vals[0]) != descriptor:
                continue
            class_data_off, static_values_off = vals[6], vals[7]
            if class_data_off == 0:
                return {}
            p = class_data_off
            nsf, p = _uleb128(self.data, p)
            for _ in range(3):
                _, p = _uleb128(self.data, p)
            fields, idx = [], 0
            for _ in range(nsf):
                diff, p = _uleb128(self.data, p)
                _, p = _uleb128(self.data, p)
                idx += diff
                fields.append(self.field(idx))
            values = self._array(static_values_off)[0] if static_values_off else []
            out = {}
            for k, (_, typ, name) in enumerate(fields):
                if k < len(values):
                    v = values[k]
                elif typ == "Z":
                    v = False
                elif typ in ("B", "S", "C", "I", "J"):
                    v = 0
                else:
                    v = None
                out[name] = (typ, v)
            return out
        return None


def dex_blobs(path):
    """zip(AAB·APK)이면 그 안의 모든 dex, 아니면 파일 자체."""
    if zipfile.is_zipfile(path):
        with zipfile.ZipFile(path) as z:
            return [(n, z.read(n)) for n in z.namelist() if re.search(r"(^|/)classes\d*\.dex$", n)]
    with open(path, "rb") as f:
        return [(os.path.basename(path), f.read())]


def find_static(path, descriptor):
    for name, blob in dex_blobs(path):
        fields = Dex(blob).static_fields(descriptor)
        if fields is not None:
            return name, fields
    return None, None


# ============================================================================ 입력 판정(preflight)

def read_properties(path):
    """Java properties 의 부분집합(키=값, # 주석). 값 앞뒤 공백은 걷는다."""
    out = {}
    with open(path, encoding="utf-8") as f:
        for n, line in enumerate(f, 1):
            s = line.strip()
            if not s or s.startswith("#") or s.startswith("!"):
                continue
            if "=" not in s:
                raise Refuse(f"{os.path.basename(path)}:{n} 에 '=' 가 없다")
            k, v = s.split("=", 1)
            out[k.strip()] = v.strip()
    return out


def jwt_payload(token):
    parts = token.split(".")
    if len(parts) != 3:
        return None
    try:
        raw = base64.urlsafe_b64decode(parts[1] + "=" * (-len(parts[1]) % 4))
        return json.loads(raw.decode("utf-8"))
    except Exception:
        return None


def firebase_from_google_services(path):
    with open(path, encoding="utf-8") as f:
        doc = json.load(f)
    info = doc.get("project_info") or {}
    clients = [c for c in doc.get("client") or []
               if ((c.get("client_info") or {}).get("android_client_info") or {}).get("package_name") == PACKAGE]
    if len(clients) != 1:
        raise Refuse(f"{GS_JSON} 에 패키지 {PACKAGE} 의 앱이 정확히 하나가 아니다({len(clients)}개)")
    c = clients[0]
    keys = [k.get("current_key", "") for k in c.get("api_key") or []]
    return {
        "firebaseAppId": (c.get("client_info") or {}).get("mobilesdk_app_id", ""),
        "firebaseProjectId": info.get("project_id", ""),
        "firebaseSenderId": str(info.get("project_number", "")),
        "firebaseApiKey": keys[0] if keys else "",
    }


def read_ledger(path):
    rows = []
    if not os.path.exists(path):
        return rows
    with open(path, encoding="utf-8") as f:
        for n, line in enumerate(f, 1):
            s = line.rstrip("\n")
            if not s or s.startswith("#"):
                continue
            cols = s.split("\t")
            if len(cols) != 7 or not cols[0].isdigit():
                raise Refuse(f"판 장부 {os.path.basename(path)}:{n} 모양이 틀렸다(칸 7개, 첫 칸 정수)")
            rows.append(dict(zip(("versionCode", "versionName", "buildTime", "gitSha", "duels", "aabSha256", "uploadCertSha256"), cols)))
    return rows


def check_prod_values(values):
    """운영 값 여섯 판정. 거부는 Refuse(값을 메시지에 싣지 않는다)."""
    missing = [k for k in PROD_KEYS if not values.get(k)]
    if missing:
        raise Refuse("운영 구성이 모자란다 — 출시 판은 aingcheck.prod.{" + ",".join(PROD_KEYS) + "} 여섯을 다 넣어야 한다(빠짐: "
                     + ",".join(missing) + "). Firebase 없이 나가면 FCM 이 죽은 판이 트랙에 오른다")
    url = values["supabaseUrl"]
    if not re.fullmatch(r"https://[A-Za-z0-9.-]+(:[0-9]{1,5})?", url):
        raise Refuse("aingcheck.prod.supabaseUrl 은 경로 없는 https://호스트 여야 한다")
    host = url[len("https://"):].split(":")[0].lower()
    if host.endswith(".invalid") or host in ("localhost", "127.0.0.1"):
        raise Refuse("aingcheck.prod.supabaseUrl 이 시험 주소다(.invalid·localhost) — 출시 판은 운영 주소를 넣는다")
    key = values["supabaseAnonKey"]
    if any(ch.isspace() or ch in "\"\\$" for ch in key):
        raise Refuse("aingcheck.prod.supabaseAnonKey 에 공백·따옴표가 있다")
    payload = jwt_payload(key)
    if payload is None or payload.get("role") != "anon":
        raise Refuse("aingcheck.prod.supabaseAnonKey 가 role=anon 인 JWT 가 아니다(비밀 키를 넣지 않는다)")
    for m in FORBIDDEN_MARKERS:
        if m.decode() in key or m.decode() in json.dumps(payload):
            raise Refuse("aingcheck.prod.supabaseAnonKey 에 비밀 키 표식이 있다")
    for k in FIREBASE_KEYS:
        if not FIREBASE_SHAPES[k].match(values[k]):
            raise Refuse(f"aingcheck.prod.{k} 모양이 틀렸다(앱의 FirebaseSettings.parse 가 거절해 초기화하지 않는다)")
    if values["firebaseAppId"].split(":")[1] != values["firebaseSenderId"]:
        raise Refuse("Firebase 앱 id 의 발신자 번호와 senderId 가 다르다(두 프로젝트 값을 섞었다)")


def cmd_preflight(a):
    """계획(비밀 없음)과 값 파일(0600 — exec-gradle 만 읽고 지운다)을 쓴다."""
    vp = read_properties(a.version_properties)
    try:
        vc = int(vp.get("androidVersionCode", ""))
    except ValueError:
        raise Refuse("version.properties 의 androidVersionCode 가 정수가 아니다")
    vn = vp.get("androidVersionName", "")
    if not (1 <= vc <= VERSION_CODE_MAX):
        raise Refuse(f"versionCode {vc} 는 1..{VERSION_CODE_MAX} 밖이다(서버 app_build 범위 — K5)")
    if not re.fullmatch(r"[0-9]+(\.[0-9]+){1,3}", vn) or len(vn) > 32:
        raise Refuse(f"versionName '{vn}' 모양이 틀렸다(숫자.숫자… 32자 이하 — client_publish_release_v2 latest_version)")
    if a.duels not in ("on", "off"):
        raise Refuse(f"--duels 는 on 또는 off 다('{a.duels}')")
    # 판돈 이중 확인(G §8-17 #1 · 검증 지적): 커밋된 androidDuelsFromBuild 와 출시 인자가 맞아야 한다. 출시 인자 하나로는 켜지지 않는다.
    dfb_raw = vp.get("androidDuelsFromBuild")
    dfb = None
    if dfb_raw is not None:
        if not re.fullmatch(r"[0-9]{1,7}", dfb_raw) or not (1 <= int(dfb_raw) <= VERSION_CODE_MAX):
            raise Refuse(f"version.properties 의 androidDuelsFromBuild '{dfb_raw}' 는 1..{VERSION_CODE_MAX} 정수여야 한다")
        dfb = int(dfb_raw)
    if a.duels == "on" and (dfb is None or vc < dfb):
        raise Refuse("--duels on 은 커밋된 version.properties 의 androidDuelsFromBuild=N(판돈 e2e 를 통과한 빌드)이 있고 versionCode ≥ N 일 때만 받는다"
                     f"(지금 androidDuelsFromBuild={dfb_raw or '없음'} · versionCode={vc})")
    if a.duels == "off" and dfb is not None and vc >= dfb:
        raise Refuse(f"커밋된 androidDuelsFromBuild={dfb} 가 이 판(versionCode={vc})부터 판돈을 켠다 — --duels on 을 주거나, 끄려면 그 줄을 고쳐 커밋한다")
    if not re.fullmatch(r"[0-9]{8}T[0-9]{6}Z", a.build_time):
        raise Refuse("빌드 시각 모양이 틀렸다")
    if not re.fullmatch(r"[0-9a-f]{40}", a.git_sha):
        raise Refuse("커밋 SHA 모양이 틀렸다")
    if a.git_dirty == "1" and not a.allow_dirty:
        raise Refuse("작업 트리가 깨끗하지 않다(판 장부 밖 변경) — 커밋한 트리에서 출시한다. 시험 판이면 --allow-dirty")
    sha = a.git_sha + ("-dirty" if a.git_dirty == "1" else "")

    values = {}
    if a.mode == "prod":
        if a.prod_config:
            props = read_properties(a.prod_config)
            unknown = sorted(k for k in props if not k.startswith("aingcheck.prod.") or k[len("aingcheck.prod."):] not in PROD_KEYS)
            if unknown:
                raise Refuse("운영 구성 파일에 모르는 키가 있다: " + ",".join(unknown) + "(aingcheck.prod.* 여섯만)")
            values = {k[len("aingcheck.prod."):]: v for k, v in props.items()}
            mode_bits = os.stat(a.prod_config).st_mode
            if mode_bits & (stat.S_IRWXG | stat.S_IRWXO):
                print("release-android: 경고 — 운영 구성 파일이 다른 사용자에게 열려 있다(chmod 600 권장)", file=sys.stderr)
        if a.google_services:
            if any(values.get(k) for k in FIREBASE_KEYS):
                raise Refuse(f"Firebase 값이 운영 구성 파일과 {GS_JSON} 양쪽에 있다 — 한 곳에서만 받는다")
            values.update(firebase_from_google_services(a.google_services))
        check_prod_values(values)
    elif a.prod_config or a.google_services:
        raise Refuse("dryrun 은 운영 구성을 받지 않는다(.invalid 판)")

    if not re.fullmatch(r"[0-9a-f]{64}", a.upload_cert_sha256 or ""):
        raise Refuse("업로드 키 인증서 지문(SHA-256)이 없다")
    ledger = read_ledger(a.ledger) if a.mode == "prod" else []
    if ledger:
        top = max(int(r["versionCode"]) for r in ledger)
        if vc <= top:
            raise Refuse(f"versionCode {vc} 가 이미 낸 판({top}) 이하다 — 단조 증가(version.properties 의 androidVersionCode 를 올린다)")
        last_cert = ledger[-1]["uploadCertSha256"]
        if last_cert != a.upload_cert_sha256 and not a.new_upload_key:
            raise Refuse("업로드 키 인증서가 장부의 직전 판과 다르다(다른 키로 서명하면 Play 가 거부한다). 키를 재설정했으면 --new-upload-key")

    if a.mode == "prod" and (a.key_place not in KEY_PLACES[:2] or a.password_source not in PASSWORD_SOURCES[:2]):
        raise Refuse("운영 판의 업로드 키 자리·비밀번호 출처가 없다(--key-place secrets-dir|other · --password-source keychain|env)")
    warnings = []
    if a.mode == "prod" and a.key_place == "other":
        warnings.append("key-outside-secrets-dir: 업로드 키 파일이 ~/.aing-check-secrets/android/ 밖에 있다(G §2-3 W6-a 행)")
    if a.mode == "prod" and a.password_source == "env":
        warnings.append("password-from-env: 업로드 키 비밀번호가 키체인이 아니라 환경 변수에서 왔다(G §2-3 W6-a 행 · A§6-1)")
    for w in warnings:
        print(f"release-android: 경고 — {w}", file=sys.stderr)
    duels = 1 if a.duels == "on" else 0
    stamp = f"aingcheck-release;build={vc};version={vn};time={a.build_time};sha={sha};duels={duels}"
    plan = {
        "mode": a.mode, "package": PACKAGE, "versionCode": vc, "versionName": vn, "buildTime": a.build_time, "gitSha": sha,
        "duelsEnabled": duels == 1, "stamp": stamp, "uploadCertSha256": a.upload_cert_sha256, "targetSdk": TARGET_SDK, "minSdk": MIN_SDK,
        "supabaseHost": (values["supabaseUrl"][len("https://"):] if a.mode == "prod" else "aingcheck.invalid"),
        "firebase": a.mode == "prod",
        "allowNoIcon": bool(a.allow_no_icon),
        "duelsFromBuild": dfb,
        "inputs": {"keyPlace": a.key_place, "passwordSource": a.password_source},
        "warnings": warnings,
    }
    gradle_props = {
        "aingcheck.release.buildTime": a.build_time,
        "aingcheck.release.gitSha": sha,
        "aingcheck.release.duelsEnabled": "true" if duels else "false",
    }
    for k in PROD_KEYS:
        if a.mode == "prod":
            gradle_props["aingcheck.prod." + k] = values[k]
    # 계획의 비교값 중 비밀이 아닌 것만 계획에 남긴다. 값 파일은 0600 으로 만든다(umask 와 상관없이).
    fd = os.open(a.values_out, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        expect = {k: values.get(k, "") for k in ("supabaseUrl", "firebaseAppId", "firebaseProjectId", "firebaseSenderId")}
        # 비밀은 아니지만 계획·영수증에 싣지 않는 두 값은 SHA-256 으로만 대조한다(dex 에 실린 것이 이 구성의 값인가).
        for k in ("supabaseAnonKey", "firebaseApiKey"):
            expect[k + "Sha256"] = hashlib.sha256(values[k].encode("utf-8")).hexdigest() if values.get(k) else ""
        json.dump({"gradleProperties": gradle_props, "expect": expect}, f)
    with open(a.out, "w", encoding="utf-8") as f:
        json.dump(plan, f, ensure_ascii=False, indent=1)
    print(f"release-android: 계획 mode={a.mode} versionCode={vc} versionName={vn} time={a.build_time} sha={sha} duels={a.duels}")
    return 0


# ============================================================================ Gradle 실행(비밀은 환경 변수로만)

def cmd_exec_gradle(a):
    with open(a.values, encoding="utf-8") as f:
        doc = json.load(f)
    os.unlink(a.values)  # 읽자마자 지운다 — 디스크에 남기지 않는다
    env = dict(os.environ)
    for k in list(env):
        if k.startswith("ORG_GRADLE_PROJECT_aingcheck."):
            del env[k]  # 밖에서 새어 든 같은 이름을 쓰지 않는다
    for k, v in doc["gradleProperties"].items():
        env["ORG_GRADLE_PROJECT_" + k] = v
    argv = a.argv[1:] if a.argv and a.argv[0] == "--" else a.argv
    if not argv:
        raise Refuse("exec-gradle: 실행할 명령이 없다")
    # gradlew 는 '#!/bin/sh' 다. Linux 의 /bin/sh(dash)는 이름에 점이 있는 환경 변수(ORG_GRADLE_PROJECT_aingcheck.*)를 자식(java)에게
    # 넘기지 않고 버린다 — 맥의 /bin/sh 는 bash 라 넘긴다(W6-a 7차 CI 탐침: Linux jvm-gate 에서만 G2·G4·G4b 가 빨갰다).
    # 그래서 명령(셸 스크립트)을 언제나 bash 로 부른다. bash 는 그런 이름을 셸 변수로는 안 받아도 자식 환경에는 그대로 넘긴다.
    argv = [BASH, *argv]
    sys.stdout.flush()
    os.execve(argv[0], argv, env)


# ============================================================================ 인증서

def pem_certs_sha256(text):
    out = []
    for m in re.finditer(r"-----BEGIN CERTIFICATE-----(.*?)-----END CERTIFICATE-----", text, re.S):
        der = base64.b64decode("".join(m.group(1).split()))
        out.append(hashlib.sha256(der).hexdigest())
    return out


def cmd_cert_sha256(a):
    shas = pem_certs_sha256(sys.stdin.read())
    if not shas:
        print("release-android: 인증서가 없다", file=sys.stderr)
        return 1
    print(shas[0])
    return 0


def cmd_file_sha256(a):
    h = hashlib.sha256()
    with open(a.path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    print(h.hexdigest())
    return 0


def apksigner_sha256(text):
    m = re.findall(r"^Signer #1 certificate SHA-256 digest: ([0-9a-f]{64})$", text, re.M)
    return m[0] if len(m) == 1 else ""


# ============================================================================ 산출물 판정(verify)

def parse_badging(text):
    out = {"permissions": [], "package": {}, "label": None, "icon": None, "launcher": None}
    for line in text.splitlines():
        if line.startswith("package:"):
            out["package"] = dict(re.findall(r"(\w+)='([^']*)'", line))
        elif line.startswith("minSdkVersion:") or line.startswith("sdkVersion:"):
            out["minSdk"] = line.split(":", 1)[1].strip().strip("'")
        elif line.startswith("targetSdkVersion:"):
            out["targetSdk"] = line.split(":", 1)[1].strip().strip("'")
        elif line.startswith("uses-permission:"):
            m = re.search(r"name='([^']*)'", line)
            if m:
                out["permissions"].append(m.group(1))
        elif line.startswith("application:"):
            d = dict(re.findall(r"(\w+)='([^']*)'", line))
            out["label"], out["icon"] = d.get("label"), d.get("icon")
        elif line.startswith("launchable-activity:"):
            m = re.search(r"name='([^']*)'", line)
            out["launcher"] = m.group(1) if m else None
    return out


def read_allowlist(path):
    with open(path, encoding="utf-8") as f:
        return sorted({l.strip() for l in f if l.strip() and not l.strip().startswith("#")})


def scan_archive(path, mode):
    """압축 안 내용물: 금지 표식·금지 파일·Fixtures 자산·.invalid 개수·dex 개수. 표식 값은 싣지 않고 자리만."""
    res = {"entries": 0, "dex": 0, "markers": [], "forbiddenEntries": [], "fixtures": [], "invalidHits": 0, "mapping": None, "showcase": []}
    with zipfile.ZipFile(path) as z:
        for info in z.infolist():
            n = info.filename
            res["entries"] += 1
            low = n.lower()
            if low.endswith(FORBIDDEN_ENTRY_SUFFIXES):
                res["forbiddenEntries"].append(n)
            if ("assets/" in low) and "fixtures" in low:
                res["fixtures"].append(n)
            data = z.read(n)
            for m in FORBIDDEN_MARKERS:
                if m in data:
                    res["markers"].append(n)
            if re.search(r"(^|/)classes\d*\.dex$", n):
                res["dex"] += 1
                res["invalidHits"] += data.count(b"aingcheck.invalid")
                # dex 문자열은 MUTF-8 — 기본 다국어 평면 글자(한글·· —)는 UTF-8 과 같은 바이트다.
                res["showcase"] += [lit for lit in SHOWCASE_LITERALS if lit.encode("utf-8") in data and lit not in res["showcase"]]
            if n.endswith("com.android.tools.build.obfuscation/proguard.map"):
                res["mapping"] = data.decode("utf-8", errors="replace")
    res["markers"] = sorted(set(res["markers"]))
    return res


def _sha256_text(v):
    return hashlib.sha256(v.encode("utf-8")).hexdigest() if isinstance(v, str) and v else ""


def read_budget(path):
    """budget.properties → ({키: 바이트}, None) 또는 (None, 이유). 키는 BUDGET_KEYS 정확히, 값은 양의 정수."""
    if not path or not os.path.exists(path):
        return None, f"파일이 없다: {path}"
    try:
        props = read_properties(path)
    except Refuse as e:
        return None, str(e)
    if sorted(props) != sorted(BUDGET_KEYS):
        return None, f"키가 {sorted(BUDGET_KEYS)} 정확히가 아니다: {sorted(props)}"
    out = {}
    for k, v in props.items():
        if not re.fullmatch(r"[1-9][0-9]{0,11}", v):
            return None, f"{k}={v!r} 는 양의 정수(바이트)가 아니다"
        out[k] = int(v)
    return out, None


def cmd_verify(a):
    with open(a.plan, encoding="utf-8") as f:
        plan = json.load(f)
    expect = {}
    if a.values_expect:
        with open(a.values_expect, encoding="utf-8") as f:
            expect = json.load(f).get("expect", {})
    checks = []

    def check(name, ok, detail):
        checks.append({"name": name, "ok": bool(ok), "detail": detail})

    # ① 배지(aapt2 dump badging — 보편 APK)
    with open(a.badging, encoding="utf-8") as f:
        b = parse_badging(f.read())
    pkg = b["package"]
    check("badging.package", pkg.get("name") == PACKAGE, f"name={pkg.get('name')} 기대 {PACKAGE}")
    check("badging.versionCode", pkg.get("versionCode") == str(plan["versionCode"]), f"versionCode={pkg.get('versionCode')} 기대 {plan['versionCode']}")
    check("badging.versionName", pkg.get("versionName") == plan["versionName"], f"versionName={pkg.get('versionName')} 기대 {plan['versionName']}")
    check("badging.targetSdk", b.get("targetSdk") == TARGET_SDK, f"targetSdk={b.get('targetSdk')} 기대 {TARGET_SDK}")
    check("badging.minSdk", b.get("minSdk") == MIN_SDK, f"minSdk={b.get('minSdk')} 기대 {MIN_SDK}")
    allow = read_allowlist(a.permissions)
    perms = sorted(set(b["permissions"]))
    extra = [p for p in perms if p not in allow]
    lacking = [p for p in allow if p not in perms]
    check("badging.permissions", not extra and not lacking, f"n={len(perms)} 넘침={extra} 모자람={lacking}")
    check("badging.noAdId", not any(p.endswith(".AD_ID") for p in perms), "AD_ID 권한 0(E§9.5)")
    check("badging.launcher", b["launcher"] == LAUNCHER, f"launchable={b['launcher']}")
    icon_ok = bool(b["icon"])
    check("badging.icon", icon_ok or plan.get("allowNoIcon"), f"icon='{b['icon'] or ''}'" + ("" if icon_ok else (" (--allow-no-icon 로 넘김)" if plan.get("allowNoIcon") else " — 런처 아이콘이 없다")))

    # ② dex 정적 값(R8 뒤 산출물 — AAB 가 있으면 AAB, 아니면 APK). 빌드 도장·판돈 깃발은 실제로 깔리는 보편 APK 의 dex 에서도 잰다.
    target = a.aab or a.apk

    def stamp_checks(prefix, path):
        where, bc = find_static(path, BUILD_CONFIG)
        stamp = bc.get("RELEASE_STAMP", (None, None))[1] if bc else None
        duels = bc.get("DUELS_ENABLED", (None, None))[1] if bc else None
        check(prefix + "releaseStamp", stamp == plan["stamp"], f"{os.path.basename(path)}:{where}: RELEASE_STAMP={stamp!r} 기대 {plan['stamp']!r}")
        check(prefix + "duelsEnabled", bc is not None and "DUELS_ENABLED" in bc and duels is plan["duelsEnabled"],
              f"{os.path.basename(path)}: DUELS_ENABLED={duels} 기대 {plan['duelsEnabled']}")

    stamp_checks("dex.", target)
    if a.aab:
        stamp_checks("dex.apk.", a.apk)
    _, bi = find_static(target, BUILD_IDENTITY)
    bi_vals = {k: v[1] for k, v in (bi or {}).items()}
    check("dex.buildIdentity", bi_vals.get("PLATFORM") == "android" and bi_vals.get("BUILD") == str(plan["versionCode"]) and bi_vals.get("VERSION") == plan["versionName"],
          f"BuildIdentity={bi_vals} 기대 android/{plan['versionCode']}/{plan['versionName']}")
    _, pc = find_static(target, PROD_CONFIG)
    pc_vals = {k: v[1] for k, v in (pc or {}).items()}
    fb_fields = (("FIREBASE_APP_ID", "firebaseAppId"), ("FIREBASE_PROJECT_ID", "firebaseProjectId"), ("FIREBASE_SENDER_ID", "firebaseSenderId"))
    if plan["mode"] == "prod":
        url_ok = pc_vals.get("SUPABASE_URL") == expect.get("supabaseUrl") and expect.get("supabaseUrl", "").startswith("https://")
        check("dex.prodConfig.url", url_ok, f"SUPABASE_URL 호스트={str(pc_vals.get('SUPABASE_URL'))[len('https://'):] or None} 기대 {plan['supabaseHost']}")
        ids_same = [k for k, e in fb_fields if pc_vals.get(k) == expect.get(e) and expect.get(e)]
        api_same = bool(expect.get("firebaseApiKeySha256")) and _sha256_text(pc_vals.get("FIREBASE_API_KEY")) == expect.get("firebaseApiKeySha256")
        check("dex.prodConfig.firebase", len(ids_same) == len(fb_fields) and api_same,
              f"운영 구성과 같은 칸={ids_same} · API 키 SHA-256 같음={api_same}(값은 싣지 않는다)")
        anon_same = bool(expect.get("supabaseAnonKeySha256")) and _sha256_text(pc_vals.get("SUPABASE_ANON_KEY")) == expect.get("supabaseAnonKeySha256")
        check("dex.prodConfig.anonKey", anon_same, f"anon 키 SHA-256 이 운영 구성과 같음={anon_same}(값은 싣지 않는다)")
    else:
        check("dex.prodConfig.url", pc_vals.get("SUPABASE_URL") == INVALID_URL, f"SUPABASE_URL={pc_vals.get('SUPABASE_URL')} 기대 {INVALID_URL}(dryrun)")
        fb_empty = [k for k in ("FIREBASE_APP_ID", "FIREBASE_PROJECT_ID", "FIREBASE_SENDER_ID", "FIREBASE_API_KEY") if pc_vals.get(k) == ""]
        check("dex.prodConfig.firebase", len(fb_empty) == 4, f"Firebase 넷 빈 값(dryrun) — 빈 칸 {len(fb_empty)}/4")
        check("dex.prodConfig.anonKey", pc_vals.get("SUPABASE_ANON_KEY") == "", "anon 빈 값(dryrun)" + ("" if pc_vals.get("SUPABASE_ANON_KEY") == "" else " — 값이 실렸다·클래스 없음"))

    # ③ 내용물(AAB·APK 둘 다)
    mapping_text = None
    for label, path in (("aab", a.aab), ("apk", a.apk)):
        if not path:
            continue
        s = scan_archive(path, plan["mode"])
        check(f"{label}.dexPresent", s["dex"] >= 1, f"dex={s['dex']} entries={s['entries']}")
        check(f"{label}.forbiddenMarkers", not s["markers"], f"비밀 표식이 든 항목={s['markers'][:10]}")
        check(f"{label}.forbiddenEntries", not s["forbiddenEntries"], f"금지 파일={s['forbiddenEntries'][:10]}")
        check(f"{label}.fixtures", not s["fixtures"], f"assets Fixtures={s['fixtures'][:10]}")
        check(f"{label}.showcaseStrings", not s["showcase"], f"dex 에 진열장 전용 문자열={s['showcase']}" if s["showcase"] else "진열장 전용 문자열 0")
        if plan["mode"] == "prod":
            check(f"{label}.noInvalidHost", s["invalidHits"] == 0, f"dex 의 aingcheck.invalid={s['invalidHits']}(운영 판은 0)")
        else:
            check(f"{label}.invalidBaseline", s["invalidHits"] >= 1, f"dex 의 aingcheck.invalid={s['invalidHits']}(dryrun 기준선 ≥1)")
        if s["mapping"] is not None:
            mapping_text = s["mapping"]
    if a.mapping and mapping_text is None and os.path.exists(a.mapping):
        with open(a.mapping, encoding="utf-8", errors="replace") as f:
            mapping_text = f.read()
    if mapping_text is None:
        check("r8.mapping", False, "R8 mapping 이 없다(minify 꺼짐?)")
    else:
        kept = sorted({l.split(" -> ")[0] for l in mapping_text.splitlines() if l and not l.startswith((" ", "#")) and l.startswith(SHOWCASE_PREFIXES)})
        check("r8.showcaseRemoved", not kept, f"진열장 클래스가 출시 판에 남았다={kept[:5]}" if kept else "진열장(AingGallery) 0 — R8 이 지웠다")
        check("r8.mapping", " -> " in mapping_text, f"mapping 줄={mapping_text.count(chr(10))}")

    # ④ 서명
    want = plan["uploadCertSha256"]
    if a.aab:
        check("sign.aab", a.aab_cert_sha256 == want and a.aab_jarsigner_rc == 0, f"AAB 서명자 지문 일치={a.aab_cert_sha256 == want} jarsigner -verify rc={a.aab_jarsigner_rc}")
    got_apk = ""
    if a.apksigner_out:
        with open(a.apksigner_out, encoding="utf-8") as f:
            got_apk = apksigner_sha256(f.read())
    check("sign.apk", got_apk == want and a.apksigner_rc == 0, f"APK 서명자 지문 일치={got_apk == want} apksigner rc={a.apksigner_rc}")

    # ⑤ 네이티브(.so 허용 목록 · 16 KB — scripts/apk-native-check.sh)
    check("native.allowlistAnd16k", a.native_rc == 0, f"apk-native-check.sh rc={a.native_rc}")

    sizes = {}
    for label, path in (("aab", a.aab), ("apk", a.apk)):
        if path:
            with open(path, "rb") as f:
                data = f.read()
            sizes[label] = {"bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()}
            with zipfile.ZipFile(path) as z:
                fonts = [i for i in z.infolist() if i.filename.lower().endswith((".otf", ".ttf"))]
                sizes[label]["fonts"] = {"files": len(fonts), "bytes": sum(i.file_size for i in fonts), "compressed": sum(i.compress_size for i in fonts)}
    # ⑥ 크기 예산(G §8-14 Pretendard — 넘으면 빨강. 값은 budget.properties, 바꿀 때는 이유를 그 파일에 적는다)
    budget, berr = read_budget(a.budget)
    if budget is None:
        check("budget.file", False, f"크기 예산 파일을 못 읽었다 — {berr}")
    else:
        if "aab" in sizes:
            check("budget.aabBytes", sizes["aab"]["bytes"] <= budget["aabMaxBytes"], f"AAB {sizes['aab']['bytes']:,}B ≤ {budget['aabMaxBytes']:,}B")
        check("budget.apkBytes", sizes["apk"]["bytes"] <= budget["apkMaxBytes"], f"보편 APK {sizes['apk']['bytes']:,}B ≤ {budget['apkMaxBytes']:,}B")
        font_bytes = max(v["fonts"]["bytes"] for v in sizes.values())
        check("budget.fontBytes", font_bytes <= budget["fontMaxBytes"], f"글꼴(.otf·.ttf) {font_bytes:,}B ≤ {budget['fontMaxBytes']:,}B")
    failed = [c for c in checks if not c["ok"]]
    receipt = dict(plan)
    receipt.update({"checks": checks, "failed": len(failed), "artifacts": sizes, "ok": not failed})
    with open(a.out, "w", encoding="utf-8") as f:
        json.dump(receipt, f, ensure_ascii=False, indent=1)
    for c in checks:
        print(f"release-android: {'OK  ' if c['ok'] else 'FAIL'} {c['name']} — {c['detail']}")
    print(f"release-android: verify checks={len(checks)} failed={len(failed)} receipt={a.out}")
    return 0 if not failed else 1


# ============================================================================ 장부·서버 채널

def cmd_ledger_append(a):
    with open(a.receipt, encoding="utf-8") as f:
        r = json.load(f)
    if not r.get("ok") or r.get("mode") != "prod":
        raise Refuse("장부에는 판정이 초록인 운영 판만 적는다")
    rows = read_ledger(a.ledger)
    if rows and int(r["versionCode"]) <= max(int(x["versionCode"]) for x in rows):
        raise Refuse("장부에 같거나 큰 versionCode 가 이미 있다")
    line = "\t".join([str(r["versionCode"]), r["versionName"], r["buildTime"], r["gitSha"], "1" if r["duelsEnabled"] else "0",
                      r["artifacts"]["aab"]["sha256"], r["uploadCertSha256"]])
    with open(a.ledger, "a", encoding="utf-8") as f:
        f.write(line + "\n")
    print(f"release-android: 판 장부에 적었다 versionCode={r['versionCode']}")
    return 0


def cmd_publish_sql(a):
    """client_publish_release_v2 호출 글자(서버 비밀 키 전용 함수 — 실행하지 않는다. 사용자 동석으로 조정자가 돌린다, G §8-9)."""
    with open(a.receipt, encoding="utf-8") as f:
        r = json.load(f)
    if not r.get("ok") or r.get("mode") != "prod":
        raise Refuse("판정이 초록인 운영 판의 영수증만 받는다")
    latest = int(r["versionCode"])
    if not (1 <= a.min_build <= latest <= VERSION_CODE_MAX):
        raise Refuse(f"min_build {a.min_build} 는 1..{latest}(이번 판) 이어야 한다")
    notes = (a.notes or "").strip()
    if len(notes) > 1000:
        raise Refuse("notes 는 1000자 이하")
    q = lambda s: "null" if s is None or s == "" else "'" + s.replace("'", "''") + "'"
    print(f"select public.client_publish_release_v2('android', {a.min_build}, {latest}, {q(notes)}, {q(r['versionName'])}, null);")
    return 0


# ============================================================================ smoke 판정(에뮬레이터에서 모은 글자 → 초록·빨강)

def judge_smoke(texts, expect_firebase=None, want_vc=None, shot_rc=0):
    """texts: seal·install·apkhash·start·pid·logcat·dumpsys·windows 글자. 돌려주는 것: [(이름, 초록?, 근거)]."""
    out = []
    lines = texts.get("logcat", "").replace("\r", "").splitlines()
    seal = (texts.get("seal", "").strip().splitlines() or [""])[-1]
    out.append(("seal", "verdict=sealed" in seal, seal[-160:]))
    inst = (texts.get("install", "").strip().splitlines() or [""])[-1]
    out.append(("install", inst.startswith("Success"), inst))
    start = texts.get("start", "").replace("\r", "")
    out.append(("amStart", re.search(r"^Status: ok$", start, re.M) is not None, " ".join(re.findall(r"^(?:Status|TotalTime): \S+", start, re.M))))
    pid = texts.get("pid", "").strip()
    out.append(("alive", re.fullmatch(r"[0-9]+", pid) is not None, f"pid={pid or '없음'}(6초 뒤)"))
    # brief 형식: "I/태그( pid): 글" — 태그가 8자보다 짧으면 공백으로 채운다("I/AingApp ( 4231)"), 길면 붙는다("I/AingShell( 4231)").
    tag = lambda t: [l for l in lines if re.match(r"^[VDIWEF]/" + t + r" *\(", l)]
    app = tag("AingApp")
    app_line = app[-1] if app else ""
    out.append(("variantRelease", "variant=RELEASE" in app_line, app_line or "AingApp 줄 없음"))
    if expect_firebase:
        out.append(("firebase", f"firebase={expect_firebase} " in app_line, f"기대 firebase={expect_firebase}"))
    shell = [l for l in tag("AingShell") if ": onCreate " in l]
    out.append(("shellOnCreate", bool(shell), shell[-1] if shell else "AingShell onCreate 줄 없음"))
    crash = [l for l in lines if "FATAL EXCEPTION" in l or re.search(r"Process: com\.yehsung\.aingcheck\b", l)]
    out.append(("noCrash", not crash, crash[0] if crash else "FATAL 0"))
    hashes = dict(re.findall(r"^(local|device)=(\S+)", texts.get("apkhash", ""), re.M))
    same = bool(re.fullmatch(r"[0-9a-f]{64}", hashes.get("local", ""))) and hashes.get("local") == hashes.get("device")
    out.append(("installedApk", same, f"깔린 base.apk SHA-256 = 이번 APK: {same} (device={hashes.get('device', '없음')[:12]} local={hashes.get('local', '없음')[:12]})"))
    if want_vc is not None:
        m = re.search(r"versionCode=([0-9]+)", texts.get("dumpsys", ""))
        out.append(("installedVersionCode", bool(m) and m.group(1) == str(want_vc), f"깔린 versionCode={m.group(1) if m else None} 기대 {want_vc}"))
    win = (texts.get("windows", "").strip().splitlines() or [""])[-1]
    out.append(("windows", win.startswith("windows_own=0 "), win[:120]))
    out.append(("screenshot", shot_rc == 0, f"shot rc={shot_rc}"))
    return out


def cmd_smoke_judge(a):
    texts = {}
    for k in ("seal", "install", "apkhash", "start", "pid", "logcat", "dumpsys", "windows"):
        p = os.path.join(a.dir, k + ".txt")
        texts[k] = open(p, encoding="utf-8", errors="replace").read() if os.path.exists(p) else ""
    res = judge_smoke(texts, a.expect_firebase, a.want_version_code, a.shot_rc)
    for name, ok, detail in res:
        print(f"release-android: smoke {'OK  ' if ok else 'FAIL'} {name} — {detail}")
    bad = [r for r in res if not r[1]]
    print(f"release-android: smoke checks={len(res)} failed={len(bad)}")
    return 0 if not bad else 1


def cmd_dex_fields(a):
    where, fields = find_static(a.path, a.descriptor)
    print(json.dumps({"where": where, "fields": None if fields is None else {k: v[1] for k, v in fields.items()}}, ensure_ascii=False))
    return 0 if fields is not None else 1


# ============================================================================ 진입

def main(argv):
    p = argparse.ArgumentParser(prog="release_tool.py")
    sub = p.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("preflight")
    s.add_argument("--mode", choices=["prod", "dryrun"], required=True)
    s.add_argument("--version-properties", required=True)
    s.add_argument("--ledger", required=True)
    s.add_argument("--prod-config")
    s.add_argument("--google-services")
    s.add_argument("--duels", default="off")
    s.add_argument("--build-time", required=True)
    s.add_argument("--git-sha", required=True)
    s.add_argument("--git-dirty", choices=["0", "1"], required=True)
    s.add_argument("--allow-dirty", action="store_true")
    s.add_argument("--allow-no-icon", action="store_true")
    s.add_argument("--upload-cert-sha256", default="")
    s.add_argument("--new-upload-key", action="store_true")
    s.add_argument("--key-place", choices=list(KEY_PLACES), default="throwaway")
    s.add_argument("--password-source", choices=list(PASSWORD_SOURCES), default="throwaway")
    s.add_argument("--out", required=True)
    s.add_argument("--values-out", required=True)
    s = sub.add_parser("exec-gradle")
    s.add_argument("--values", required=True)
    s.add_argument("argv", nargs=argparse.REMAINDER)
    sub.add_parser("cert-sha256")
    s = sub.add_parser("file-sha256")
    s.add_argument("path")
    s = sub.add_parser("verify")
    s.add_argument("--plan", required=True)
    s.add_argument("--values-expect")
    s.add_argument("--aab")
    s.add_argument("--apk", required=True)
    s.add_argument("--badging", required=True)
    s.add_argument("--mapping")
    s.add_argument("--permissions", required=True)
    s.add_argument("--aab-cert-sha256", default="")
    s.add_argument("--aab-jarsigner-rc", type=int, default=1)
    s.add_argument("--apksigner-out")
    s.add_argument("--apksigner-rc", type=int, default=1)
    s.add_argument("--native-rc", type=int, default=1)
    s.add_argument("--budget", required=True)
    s.add_argument("--out", required=True)
    s = sub.add_parser("ledger-append")
    s.add_argument("--receipt", required=True)
    s.add_argument("--ledger", required=True)
    s = sub.add_parser("publish-sql")
    s.add_argument("--receipt", required=True)
    s.add_argument("--min-build", type=int, required=True)
    s.add_argument("--notes")
    s = sub.add_parser("smoke-judge")
    s.add_argument("--dir", required=True)
    s.add_argument("--expect-firebase", choices=["INITIALIZE", "SKIP_NO_CONFIG"])
    s.add_argument("--want-version-code", type=int)
    s.add_argument("--shot-rc", type=int, default=0)
    s = sub.add_parser("dex-fields")
    s.add_argument("path")
    s.add_argument("descriptor")
    s = sub.add_parser("self-test")
    s.add_argument("--script", required=True)
    a = p.parse_args(argv)
    try:
        if a.cmd == "self-test":
            here = os.path.dirname(os.path.abspath(__file__))
            sys.path.insert(0, here)
            sys.dont_write_bytecode = True  # 저장소 안에 __pycache__ 를 남기지 않는다
            import release_selftest  # noqa: E402 — 같은 폴더(자기 시험은 따로 둔다)
            return release_selftest.run(a.script, os.path.abspath(__file__))
        return {
            "preflight": cmd_preflight, "exec-gradle": cmd_exec_gradle, "cert-sha256": cmd_cert_sha256, "file-sha256": cmd_file_sha256, "verify": cmd_verify,
            "ledger-append": cmd_ledger_append, "publish-sql": cmd_publish_sql, "dex-fields": cmd_dex_fields, "smoke-judge": cmd_smoke_judge,
        }[a.cmd](a)
    except Refuse as e:
        print(f"release-android: 거부 — {e}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
