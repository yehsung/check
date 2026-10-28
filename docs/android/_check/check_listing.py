#!/usr/bin/env python3
# 원본: 없음 (Swift 짝 없음 — Google Play 제출 초안 검사기, W6-c)
"""docs/android 초안 검사기.

G §2-3 W6-c 완료 기준을 글자로 잰다.
  ① 확률 숫자 0      — 모든 .md 에 백분율 기호·'퍼센트'·'percent' 가 없다(확률은 서버 값, E §9.4).
  ② 낡은 문장 0      — 영어 심사 지시문 두 칸에 iOS 노트의 낡은 문구가 없고, 꼭 있어야 할 문구는 있다.
  ③ E §9.3·9.5 일치  — data-safety.md §2 표와 content-rating.md §2 표의 답이 설계 E 의 표와 같다.
덧붙여 공개 저장소 규칙(자격증명·이메일·긴 계정 번호·비밀 문형 0)과 콘솔 글자 수 한도를 잰다.

실행(저장소 뿌리에서):
  python3 -I docs/android/_check/check_listing.py              # 검사 — 위반이 있으면 종료 1
  python3 -I docs/android/_check/check_listing.py --self-test  # 결함을 심은 사본이 빨개지는지
  python3 -I docs/android/_check/check_listing.py --docs <폴더> # 다른 사본을 잴 때

★ 기대값(E_DATA_SAFETY · E_IARC)은 구현을 거울처럼 옮긴 것이 아니라 설계 E §9.5·§9.3 의 표다. 답을 바꾸려면 설계(E)를 먼저
  고치고 여기 기대값을 같은 커밋에서 고친다 — 문서만 고치면 이 검사가 빨갛다(의도한 동작).
★ 비밀 문형은 쪼개 적는다(apk-content-check.sh 선례). 푸시 직전 비밀 검사가 이 파일 자체를 잡지 않게 하려는 것이다.
"""
import argparse
import pathlib
import re
import shutil
import sys
import tempfile

HERE = pathlib.Path(__file__).resolve().parent
DEFAULT_DOCS = HERE.parent

REQUIRED_FILES = [
    "README.md",
    "store-listing.md",
    "data-safety.md",
    "content-rating.md",
    "app-access.md",
    "app-content.md",
]

# 콘솔 입력칸 한도(Play Console — 일반 지식, 문서에 '재확인'으로 적었다). 지시문 두 칸은 이 갈래가 정한 상한이다.
FIELD_LIMITS = {
    "title": 30,
    "short_description": 80,
    "full_description": 4000,
    "release_notes": 500,
    "review_notes_short": 500,
    "review_notes_long": 4000,
}
FIELDS_BY_FILE = {
    "store-listing.md": ["title", "short_description", "full_description", "release_notes"],
    "app-access.md": ["review_notes_short", "review_notes_long"],
}
FIELD_RE = re.compile(r"<!--\s*field:\s*([a-z_]+)\s*·\s*최대\s*(\d+)자\s*-->\s*\n```text\n(.*?)\n```", re.S)

# ① 확률 숫자: 백분율 기호(반각·전각)와 그 낱말. 이 폴더는 확률·가격·상금 비율을 아예 쓰지 않는다.
ODDS_PATTERNS = [
    (re.compile("[%％]"), "백분율 기호"),
    (re.compile("퍼센트"), "'퍼센트'"),
    (re.compile(r"\bper\s?cent\b", re.I), "'percent'"),
]

# 공개 저장소 규칙: 자격증명·연락처·계정 번호·로컬 경로·비밀 문형.
PRIVACY_PATTERNS = [
    (re.compile(r"[A-Za-z0-9._+\-]+@[A-Za-z0-9\-]+(?:\.[A-Za-z0-9\-]+)*\.[A-Za-z]{2,}"), "이메일 주소"),
    (re.compile(r"(?<!\d)\d{12,}(?![\d_])"), "12자리 이상 숫자(계정·앱 번호 — 마이그레이션 이름 `<14자리>_…` 은 뺀다)"),
    (re.compile("/" + "Users/"), "로컬 홈 경로"),
    (re.compile("aing-check-" + "secrets"), "비밀 보관소 경로"),
    (re.compile("ey" + r"J[A-Za-z0-9_\-]{20,}"), "JWT 모양 문자열"),
    (re.compile("service" + "_role"), "service 역할 키 이름"),
    (re.compile("sk-" + "ant-"), "Anthropic 키 모양"),
    (re.compile("AI" + r"za[0-9A-Za-z_\-]{30,}"), "Google API 키 모양"),
    (re.compile("gh" + r"[pousr]_[A-Za-z0-9]{20}"), "GitHub 토큰 모양"),
    (re.compile("BEGIN [A-Z ]*" + "PRIVATE KEY"), "개인키 머리"),
    (re.compile(r"\.supa" + r"base\.co"), "Supabase 프로젝트 주소"),
    (re.compile("google-" + r"services\.json"), "Firebase 설정 파일 이름"),
    (re.compile(r"\.(?:jks|keystore)\b"), "서명 키 파일"),
]

# ② 영어 심사 지시문에서 0건이어야 하는 낡은 문구(app-access.md §3 표와 같은 목록). 대소문자 무시.
STALE_PATTERNS = [
    (r"only possible in the Mac app", "폰 근무 시작은 iOS 1.0.7 부터 된다"),
    (r"only in the Mac app", "폰 근무 시작은 iOS 1.0.7 부터 된다"),
    (r"done in the Mac app", "폰 근무 시작은 iOS 1.0.7 부터 된다"),
    (r"\btwo (?:quick )?mini ?games\b", "미니게임은 셋이다"),
    (r"\biPhone\b", "플랫폼이 다르다"),
    (r"\bAPNs\b", "Android 알림은 FCM 이다"),
    (r"\bApp Store\b", "플랫폼이 다르다"),
    (r"\bTestFlight\b", "플랫폼이 다르다"),
    (r"\bGuideline\b", "애플 심사 지침 번호다"),
    (r"New in 1\.", "iOS 판별 변경 블록이다"),
    (r"phone_login", "숨김 데모 계정은 미션 판정을 받지 않는다"),
    (r"already achieved", "숨김 데모 계정은 미션 판정을 받지 않는다"),
    (r"turns achieved", "숨김 데모 계정은 미션 판정을 받지 않는다"),
    (r"<[AB]_(?:EMAIL|PASSWORD)>", "자격증명을 문서 안에서 치환하던 옛 틀이다"),
    (r"\bfees?\b", "대결 수수료는 2026-10-22 에 없어졌다"),
    (r"\bCrossy\b", "Android 첫 판에 넣지 않는다(G §8-18 #7)"),
    (r"길건너", "Android 첫 판에 넣지 않는다(G §8-18 #7)"),
    (r"all-time", "역대 순위는 Android 첫 판에 넣지 않는다(G §8-18 #7)"),
]
STALE_RES = [(re.compile(p, re.I), why) for p, why in STALE_PATTERNS]

# ② 지시문에 꼭 있어야 하는 문구(지시문이 비거나 줄어든 것을 잡는다).
REQUIRED_PHRASES = {
    "review_notes_short": ["aing-check.vercel.app/delete-account", "cannot be bought", "isolated"],
    "review_notes_long": [
        "aing-check.vercel.app/delete-account",
        "cannot be bought",
        "Report",
        "Block",
        "simulated gambling",
        "Show odds",
        "isolated",
    ],
}

# ③ 설계 E §9.5 표(Play 항목 · 수집 · 필수/선택 · 목적). 공유 열은 이 문서가 더했다 — 전부 '아니오' 또는 '—'.
E_DATA_SAFETY = [
    ("개인 정보 › 이메일 주소", "예", "필수", "계정 관리 · 앱 기능"),
    ("개인 정보 › 이름", "예(별명)", "필수", "앱 기능"),
    ("개인 정보 › 사용자 ID", "예", "필수", "계정 관리"),
    ("사진 및 동영상 › 사진", "예", "선택", "앱 기능"),
    ("메시지 › 기타 인앱 메시지", "예", "선택", "앱 기능"),
    ("앱 활동 › 앱 상호작용", "예", "필수", "앱 기능"),
    ("앱 활동 › 기타 사용자 제작 콘텐츠", "예", "선택", "앱 기능"),
    ("앱 활동 › 기타 작업", "예", "필수", "앱 기능"),
    ("앱 정보 및 성능 › 기타 앱 성능 데이터", "예(보수적)", "필수", "앱 기능"),
    ("기기 또는 기타 ID", "예", "필수", "앱 기능"),
    ("위치·연락처·금융·건강·파일·캘린더·오디오·웹 기록·설치 앱·검색 기록·비정상 종료 로그", "아니오", "—", "—"),
    ("보안: 전송 중 암호화", "예", "—", "—"),
    ("보안: 삭제 요청 수단", "예", "—", "—"),
]

# ③ 설계 E §9.3 표(항목 · 초안 답의 첫머리).
E_IARC = [
    ("앱 범주", "기타(생산성·커뮤니케이션)"),
    ("폭력·공포·성적·언어·약물·저속한 유머", "없음"),
    ("실제 도박", "아니오"),
    ("모의 도박", "예"),
    ("사용자 상호작용(메시지·채팅·UGC)", "예"),
    ("위치 공유", "아니오"),
    ("디지털 상품 구매", "아니오"),
    ("무작위 아이템", "원문을 보고 고른다"),
    ("무제한 웹 접근", "아니오"),
]


def _cells(line):
    return [c.strip() for c in line.strip().strip("|").split("|")]


def _plain(cell):
    return cell.replace("**", "").strip()


def _section_rows(text, heading_prefix):
    """'## <heading_prefix>' 절 안 첫 표의 본문 행(머리·구분 줄 뺌)을 칸 목록으로 돌려준다."""
    lines = text.splitlines()
    start = None
    for i, line in enumerate(lines):
        if line.startswith("## ") and line[3:].startswith(heading_prefix):
            start = i + 1
            break
    if start is None:
        return None
    rows = []
    in_table = False
    for line in lines[start:]:
        if line.startswith("## "):
            break
        if line.startswith("|"):
            in_table = True
            rows.append(line)
        elif in_table:
            break
    body = [r for r in rows[2:]]  # 머리 줄과 구분 줄을 뺀다
    return [_cells(r) for r in body]


def check(docs):
    docs = pathlib.Path(docs)
    fails = []
    texts = {}
    for name in REQUIRED_FILES:
        p = docs / name
        if not p.is_file():
            fails.append(("files", "없는 파일: %s" % name))
        else:
            texts[name] = p.read_text(encoding="utf-8")
    md_files = sorted(p for p in docs.rglob("*.md") if "_check" not in p.relative_to(docs).parts)
    for p in md_files:
        rel = str(p.relative_to(docs))
        text = texts.get(rel) if rel in texts else p.read_text(encoding="utf-8")
        for n, line in enumerate(text.splitlines(), 1):
            for rx, what in ODDS_PATTERNS:
                if rx.search(line):
                    fails.append(("odds", "%s:%d %s" % (rel, n, what)))
            for rx, what in PRIVACY_PATTERNS:
                if rx.search(line):
                    fails.append(("privacy", "%s:%d %s" % (rel, n, what)))

    fields = {}
    for name, wanted in FIELDS_BY_FILE.items():
        text = texts.get(name)
        if text is None:
            continue
        found = {}
        for m in FIELD_RE.finditer(text):
            found[m.group(1)] = (int(m.group(2)), m.group(3))
        for key in wanted:
            if key not in found:
                fails.append(("fields", "%s: 칸 표식 없음 '%s'" % (name, key)))
                continue
            marker_limit, body = found[key]
            if marker_limit != FIELD_LIMITS[key]:
                fails.append(("limit", "%s: '%s' 표식 한도 %d ≠ 계약 %d" % (name, key, marker_limit, FIELD_LIMITS[key])))
            if len(body) > FIELD_LIMITS[key]:
                fails.append(("limit", "%s: '%s' %d자 > %d" % (name, key, len(body), FIELD_LIMITS[key])))
            if not body.strip():
                fails.append(("fields", "%s: '%s' 가 비었다" % (name, key)))
            fields[key] = body

    for key in ("review_notes_short", "review_notes_long"):
        body = fields.get(key)
        if body is None:
            continue
        for rx, why in STALE_RES:
            m = rx.search(body)
            if m:
                fails.append(("stale", "%s: 낡은 문구 '%s' — %s" % (key, m.group(0), why)))
        for phrase in REQUIRED_PHRASES[key]:
            if phrase not in body:
                fails.append(("required", "%s: 꼭 있어야 할 문구 없음 '%s'" % (key, phrase)))

    ds = texts.get("data-safety.md")
    if ds is not None:
        rows = _section_rows(ds, "2.")
        if rows is None:
            fails.append(("data-safety", "data-safety.md: '## 2.' 절이 없다"))
        else:
            got = [(_plain(r[0]), _plain(r[1]), _plain(r[3]), _plain(r[4]), _plain(r[2])) for r in rows if len(r) >= 5]
            if len(got) != len(rows):
                fails.append(("data-safety", "data-safety.md §2: 칸이 모자란 행이 있다"))
            if [g[:4] for g in got] != E_DATA_SAFETY:
                want = set(E_DATA_SAFETY)
                have = set(g[:4] for g in got)
                for miss in [w for w in E_DATA_SAFETY if w not in have]:
                    fails.append(("data-safety", "E §9.5 와 다름 — 없거나 바뀐 행: %s" % " | ".join(miss)))
                for extra in [g[:4] for g in got if g[:4] not in want]:
                    fails.append(("data-safety", "E §9.5 에 없는 행: %s" % " | ".join(extra)))
                if not [w for w in E_DATA_SAFETY if w not in have] and not [g for g in got if g[:4] not in want]:
                    fails.append(("data-safety", "E §9.5 와 행 순서가 다르다"))
            for g in got:
                if g[4] not in ("아니오", "—"):
                    fails.append(("data-safety", "공유 열은 '아니오'(서비스 제공자만) 또는 '—' 여야 한다: %s → %s" % (g[0], g[4])))

    cr = texts.get("content-rating.md")
    if cr is not None:
        rows = _section_rows(cr, "2.")
        if rows is None:
            fails.append(("iarc", "content-rating.md: '## 2.' 절이 없다"))
        else:
            got = [(_plain(r[0]), _plain(r[1])) for r in rows if len(r) >= 2]
            names = [g[0] for g in got]
            if names != [e[0] for e in E_IARC]:
                fails.append(("iarc", "E §9.3 과 항목 목록이 다르다: %s" % " / ".join(names)))
            answers = dict(got)
            for item, head in E_IARC:
                ans = answers.get(item)
                if ans is not None and not ans.startswith(head):
                    fails.append(("iarc", "E §9.3 과 답이 다르다: %s → '%s'(기대 첫머리 '%s')" % (item, ans[:30], head)))
    return fails, fields


# 결함 심기: (파일, 찾을 글자, 바꿀 글자, 빨개져야 할 종류). 찾을 글자는 원본에 정확히 한 번 있어야 한다.
MUTATIONS = [
    ("store-listing.md", "(뽑기 확률은 앱 안에 공개합니다)", "(황금 아잉이 3" + "% 확률)", "odds"),
    ("README.md", "# Google Play 제출 자료 초안", "# Google Play 제출 자료 초안 ５％", "odds"),
    ("content-rating.md", "| 디지털 상품 구매 | 아니오 |", "| 디지털 상품 구매 | 아니오(무지개 2퍼센트) |", "odds"),
    ("app-access.md", "| 안내 1 이름 | `Demo account A` |", "| 안내 1 이름 | `demo-a" + "@" + "example.com` |", "privacy"),
    ("app-content.md", "| 뉴스 앱 | 아니요 |", "| 뉴스 앱 | 아니요 " + "1234567" * 3 + " |", "privacy"),
    ("app-content.md", "| 정부 앱 | 아니요 |", "| 정부 앱 | " + "service" + "_role |", "privacy"),
    ("data-safety.md", "| 보안: 전송 중 암호화 |", "| 보안: 전송 중 암호화 /" + "Users/someone |", "privacy"),
    ("store-listing.md", "우리 팀이 지금 누가 일하는지 한눈에.", "우리 팀이 지금 누가 일하는지 한눈에. " + "가" * 40, "limit"),
    ("store-listing.md", "<!-- field: short_description · 최대 80자 -->", "<!-- field: short_description · 최대 90자 -->", "limit"),
    ("store-listing.md", "<!-- field: release_notes · 최대 500자 -->\n", "", "fields"),
    ("app-access.md", "What this app is\n", "What this app is\nStarting and ending work is only possible in the Mac app.\n", "stale"),
    ("app-access.md", "Sign in with this demo account", "Sign in on your iPhone with this demo account", "stale"),
    ("app-access.md", "The app has no ads,", "There is no duel fee. The app has no ads,", "stale"),
    ("app-access.md", "On the web, without the app: https://aing-check.vercel.app/delete-account", "On the web: (soon)", "required"),
    ("data-safety.md", "| 사진 및 동영상 › 사진 | 예 | 아니오 | 선택 |", "| 사진 및 동영상 › 사진 | 예 | 아니오 | 필수 |", "data-safety"),
    ("data-safety.md", "| 메시지 › 기타 인앱 메시지 | 예 | 아니오 |", "| 메시지 › 기타 인앱 메시지 | 예 | 예 |", "data-safety"),
    ("data-safety.md", "| 개인 정보 › 사용자 ID |", "| 개인 정보 › 기타 정보 |", "data-safety"),
    ("content-rating.md", "| 모의 도박 | **예(추천)**", "| 모의 도박 | **아니오**", "iarc"),
    ("content-rating.md", "| 위치 공유 | 아니오 |", "| 위치 공유 | 예 |", "iarc"),
]


def self_test():
    problems = []
    with tempfile.TemporaryDirectory(prefix="w6c-listing-") as tmp:
        base = pathlib.Path(tmp) / "pristine"
        shutil.copytree(DEFAULT_DOCS, base, ignore=shutil.ignore_patterns("_check", "__pycache__"))
        fails, _ = check(base)
        if fails:
            problems.append("원본이 이미 빨갛다: %s" % fails[:3])
        for i, (name, old, new, kind) in enumerate(MUTATIONS):
            copy = pathlib.Path(tmp) / ("m%02d" % i)
            shutil.copytree(base, copy)
            p = copy / name
            text = p.read_text(encoding="utf-8")
            if text.count(old) != 1:
                problems.append("결함 %02d: 심을 자리 '%s' 가 %s 에 %d번 있다(1번이어야 한다)" % (i, old[:30], name, text.count(old)))
                continue
            p.write_text(text.replace(old, new), encoding="utf-8")
            got, _ = check(copy)
            kinds = sorted(set(k for k, _ in got))
            if kind not in kinds:
                problems.append("결함 %02d(%s, %s) 이 빨개지지 않았다 — 나온 종류 %s" % (i, kind, name, kinds))
        # 없는 파일
        copy = pathlib.Path(tmp) / "missing"
        shutil.copytree(base, copy)
        (copy / "content-rating.md").unlink()
        got, _ = check(copy)
        if "files" not in set(k for k, _ in got):
            problems.append("파일을 지운 사본이 빨개지지 않았다")
    total = len(MUTATIONS) + 1
    if problems:
        for p in problems:
            print("self-test: FAIL %s" % p)
        print("self-test: %d/%d 결함 중 실패 %d" % (total, total, len(problems)))
        return 1
    print("self-test: 원본 초록 · 심은 결함 %d/%d 전부 빨강" % (total, total))
    return 0


def main(argv=None):
    ap = argparse.ArgumentParser(description="docs/android 초안 검사기(W6-c)")
    ap.add_argument("--docs", default=str(DEFAULT_DOCS))
    ap.add_argument("--self-test", action="store_true")
    args = ap.parse_args(argv)
    if args.self_test:
        return self_test()
    fails, fields = check(args.docs)
    for kind, msg in fails:
        print("check_listing: FAIL [%s] %s" % (kind, msg))
    lens = " ".join("%s=%d/%d" % (k, len(fields[k]), FIELD_LIMITS[k]) for k in FIELD_LIMITS if k in fields)
    print("check_listing: files=%d fields=%d %s failures=%d" % (len(REQUIRED_FILES), len(fields), lens, len(fails)))
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
