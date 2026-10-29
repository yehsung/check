#!/usr/bin/env python3
# 원본: 없음 (Swift 짝 없음 — Google Play 제출 초안 검사기, W6-c)
"""docs/android 초안 검사기.

G §2-3 W6-c 완료 기준을 글자로 잰다.
  ① 확률 숫자 0      — 모든 .md 에 확률·비율 숫자 꼴이 없다(확률은 서버 값, E §9.4).
                        백분율 기호·낱말, '3프로', 'N번에 M번', 'N분의 M', 'N in M', '0.03' 같은 소수,
                        그리고 확률 낱말(확률·당첨·odds·chance…)이 든 문장 안의 숫자.
  ② 낡은 문장 0      — 콘솔에 옮길 여섯 칸(등록정보 넷 + 영어 지시문 둘)에 낡은 문구가 없고, 꼭 있어야 할 문구는 있다.
                        금지 목록은 한 벌이고 여섯 칸 모두에 건다(§8-18 #7 길건너·역대, 플랫폼 낱말, 옛 이름, 수수료 …).
  ③ E §9.3·9.5 일치  — data-safety.md §2 표와 content-rating.md §2 표의 답 칸이 설계 E 의 표와 **글자로** 같다.
덧붙여 공개 저장소 규칙(자격증명·이메일·긴 계정 번호·비밀 문형 0)과 콘솔 글자 수 한도를 잰다.

실행(저장소 뿌리에서):
  python3 -I docs/android/_check/check_listing.py              # 검사 — 위반이 있으면 종료 1
  python3 -I docs/android/_check/check_listing.py --self-test  # 규칙마다 결함을 심은 사본이 바로 그 규칙으로 빨개지는지
  python3 -I docs/android/_check/check_listing.py --docs <폴더> # 다른 사본을 잴 때
  python3 -I docs/android/_check/check_listing.py --e-source <E-android-platform.md>
                                                               # 기대값(E_DATA_SAFETY·E_IARC)이 설계 E 원문 표와 같은지
                                                               # (설계서는 저장소 밖이라 CI 는 돌리지 않는다 — 사람이 돌린다)

★ 기대값(E_DATA_SAFETY · E_IARC)은 구현을 거울처럼 옮긴 것이 아니라 설계 E §9.5·§9.3 표의 원문 글자다(--e-source 로 잰다).
  답을 바꾸려면 설계(E)를 먼저 고치고 여기 기대값을 같은 커밋에서 고친다 — 문서만 고치면 이 검사가 빨갛다(의도한 동작).
  E 원문에서 문서가 일부러 뺀 글자는 E_IARC_EDITS 에만 적는다(이유와 함께). 그 밖의 차이는 전부 빨강이다.
★ 규칙마다 결함 표본을 규칙 바로 옆에 둔다. self-test 는 (가) 규칙 이름 목록이 SELF_TEST_PINS 와 같은지,
  (나) 표본을 문서에 심은 사본이 **그 규칙 이름으로** 빨개지는지 잰다. 규칙 하나를 지우면 (가)가, 규칙 하나를 망가뜨리면
  (나)가 빨갛다. 규칙을 더하거나 빼는 일은 규칙과 SELF_TEST_PINS 를 같은 커밋에서 고치는 일이다.
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


# ── ① 확률 숫자 ───────────────────────────────────────────────────────────────────────────────
# 확률 낱말이 든 문장에서 숫자로 치지 않는 것: 코드 조각·설계 절 번호·버전·갈래 이름·'1:1'·주소.
ODDS_WORDS = re.compile(r"확률|당첨|출현율|등장률|\bodds\b|\bchances?\b|probabilit", re.I)
NOT_ODDS_NUMBERS = [
    re.compile(r"`[^`]*`"),
    re.compile(r"https?://\S+"),
    re.compile(r"§\s*\d+(?:[.\-]\d+)*(?:\s*[·~,]\s*\d+(?:[.\-]\d+)*)*"),
    re.compile(r"\b\d+(?:\.\d+){2,}\b"),
    re.compile(r"\b[WK]\d+(?:-[a-z0-9]+)?\b"),
    re.compile(r"\b1:1\b"),
]
SENTENCE_SPLIT = re.compile(r"(?<=[.!?。])\s+|\s+—\s+|\|")


def _odds_sentence(line):
    """확률 낱말이 든 문장(표 칸·'—' 마디 포함)에 숫자가 남아 있으면 참."""
    for sentence in SENTENCE_SPLIT.split(line):
        if not ODDS_WORDS.search(sentence):
            continue
        rest = sentence
        for rx in NOT_ODDS_NUMBERS:
            rest = rx.sub(" ", rest)
        if re.search(r"\d", rest):
            return True
    return False


def _rx(pattern, flags=0):
    return re.compile(pattern, flags).search


# (이름, 판정 함수, 설명, 결함 표본). 이 폴더는 확률·가격·상금 비율을 아예 쓰지 않는다.
ODDS_RULES = [
    ("pct-sign", _rx("[%％‰﹪]"), "백분율 기호", "황금 아잉이 3" + "%"),
    ("pct-word-ko", _rx("퍼센트|프로센트"), "'퍼센트'", "무지개 2퍼센트"),
    ("pct-word-en", _rx(r"\bper\s?cents?\b|\bpct\b", re.I), "'percent'", "a 3 percent draw"),
    ("pct-pro", _rx(r"\d\s*프로(?!필|젝|덕|그|세|모|토|파|미|퍼|듀|스|틴|포|펠|브)"), "숫자 뒤 '프로'", "황금 아잉이 3프로"),
    ("n-in-m-ko", _rx(r"\d+\s*(?:번|회|판|명)\s*(?:에|중에?|당)\s*\d+\s*(?:번|회|판|명)"), "'N번에 M번' 꼴",
     "100번에 3번 꼴로 나온다"),
    ("fraction-ko", _rx(r"\d+\s*분의\s*\d+"), "'N분의 M' 꼴", "100분의 3 로 나온다"),
    ("n-in-m-en", _rx(r"\b\d+\s+(?:in|out\s+of)\s+(?:every\s+)?\d+\b", re.I), "'N in M' 꼴", "Golden Aing 3 in 100"),
    ("decimal-fraction", _rx(r"(?<![\d.])0?\.\d+(?![\d.])"), "1보다 작은 소수(0.03 · .03 꼴)", "황금 아잉이 0.03"),
    ("odds-sentence", _odds_sentence, "확률 낱말이 든 문장 안의 숫자", "황금 아잉이 확률은 3 이다."),
]

# ── 공개 저장소 규칙 ─────────────────────────────────────────────────────────────────────────
# (이름, 정규식, 설명, 결함 표본) — 표본도 쪼개 적는다.
PRIVACY_RULES = [
    ("email", r"[A-Za-z0-9._+\-]+@[A-Za-z0-9\-]+(?:\.[A-Za-z0-9\-]+)*\.[A-Za-z]{2,}", "이메일 주소",
     "demo-a" + "@" + "example.com"),
    ("long-number", r"(?<!\d)\d{12,}(?![\d_])", "12자리 이상 숫자(계정·앱 번호 — 마이그레이션 이름 `<14자리>_…` 은 뺀다)",
     "1234567" * 3),
    ("home-path", "/" + "Users/", "로컬 홈 경로", "/" + "Users/someone/x"),
    ("secret-store", "aing-check-" + "secrets", "비밀 보관소 경로", "~/." + "aing-check-" + "secrets/x"),
    ("jwt", "ey" + r"J[A-Za-z0-9_\-]{20,}", "JWT 모양 문자열", "ey" + "J" + "a" * 24),
    ("service-role", "service" + "_role", "service 역할 키 이름", "service" + "_role"),
    ("anthropic-key", "sk-" + "ant-", "Anthropic 키 모양", "sk-" + "ant-" + "x"),
    ("google-key", "AI" + r"za[0-9A-Za-z_\-]{30,}", "Google API 키 모양", "AI" + "za" + "B" * 33),
    ("github-token", "gh" + r"[pousr]_[A-Za-z0-9]{20}", "GitHub 토큰 모양", "gh" + "p_" + "C" * 22),
    ("private-key", "BEGIN [A-Z ]*" + "PRIVATE KEY", "개인키 머리", "BEGIN " + "RSA " + "PRIVATE KEY"),
    ("supabase-host", r"\.supa" + r"base\.co", "Supabase 프로젝트 주소", "x.supa" + "base.co"),
    ("firebase-config", "google-" + r"services\.json", "Firebase 설정 파일 이름", "google-" + "services.json"),
    ("signing-key", r"\.(?:jks|keystore)\b", "서명 키 파일", "upload." + "jk" + "s"),
    ("phone-number", r"(?<![\d.])0\d{1,2}[-. ]?\d{3,4}[-. ]?\d{4}(?!\d)|\+\d{1,3}[-. ]?\d{1,2}[-. ]?\d{3,4}[-. ]?\d{4}(?!\d)",
     "전화번호", "010-" + "1234-" + "5678"),
]
PRIVACY_RES = [(i, re.compile(p), what, sample) for i, p, what, sample in PRIVACY_RULES]

# ── ② 콘솔 여섯 칸의 낡은 문구 ───────────────────────────────────────────────────────────────
# (이름, 정규식, 왜 낡았나, 결함 표본). 대소문자 무시. 여섯 칸 모두에 건다(app-access.md §3 · store-listing.md §3.3 표).
STALE_RULES = [
    ("mac-only-possible", r"only possible in the Mac app", "폰 근무 시작은 iOS 1.0.7 부터 된다",
     "Starting work is only possible in the Mac app."),
    ("mac-only-in", r"only in the Mac app", "폰 근무 시작은 iOS 1.0.7 부터 된다", "It works only in the Mac app."),
    ("mac-only-done", r"done in the Mac app", "폰 근무 시작은 iOS 1.0.7 부터 된다", "This is done in the Mac app."),
    ("mac-only-en", r"\bonly\b[^.;:]{0,60}\bMac\b|\bMac\b[^.;:]{0,30}\bonly\b|\bnot on the phone\b",
     "폰 근무 시작은 iOS 1.0.7 부터 된다(낱말 순서가 바뀐 꼴)", "A session can only be started on the Mac, not on the phone."),
    ("mac-only-ko", r"맥(?:\s*앱)?(?:에서)?만", "폰 근무 시작은 iOS 1.0.7 부터 된다", "근무 시작은 맥에서만 됩니다."),
    ("two-games-en", r"\btwo (?:quick )?mini[\s-]?games?\b", "미니게임은 셋이다", "two mini-games"),
    ("two-games-ko", r"(?:두|2)\s*(?:가지|개|종)\s*미니\s*게임|미니\s*게임\s*(?:두|2)\s*(?:가지|개|종)|미니\s*게임\s*둘",
     "미니게임은 셋이다", "두 가지 미니게임"),
    ("iphone", r"\biPhone\b|아이폰", "플랫폼이 다르다", "아이폰 앱입니다"),
    ("ios", r"\biOS\b", "플랫폼이 다르다", "the iOS app"),
    ("apns", r"\bAPNs\b", "Android 알림은 FCM 이다", "APNs push"),
    ("app-store", r"\bApp Store\b|앱\s?스토어", "플랫폼이 다르다", "앱스토어 평점"),
    ("testflight", r"\bTestFlight\b|테스트\s?플라이트", "플랫폼이 다르다", "TestFlight build"),
    ("guideline", r"\bGuideline\b", "애플 심사 지침 번호다", "Guideline 2.3.6"),
    ("new-in", r"New in 1\.", "iOS 판별 변경 블록이다", "New in 1.0.13"),
    ("phone-login", r"phone_login", "숨김 데모 계정은 미션 판정을 받지 않는다", "phone_login"),
    ("already-achieved", r"already achieved", "숨김 데모 계정은 미션 판정을 받지 않는다", "is already achieved"),
    ("turns-achieved", r"turns achieved", "숨김 데모 계정은 미션 판정을 받지 않는다", "the row turns achieved"),
    ("cred-template", r"<[AB]_(?:EMAIL|PASSWORD)>", "자격증명을 문서 안에서 치환하던 옛 틀이다", "<A_" + "EMAIL>"),
    ("fee-en", r"\bfees?\b", "대결 수수료는 2026-10-22 에 없어졌다", "a duel fee"),
    ("fee-ko", r"수수료", "대결 수수료는 2026-10-22 에 없어졌다", "판돈 수수료"),
    ("crossy", r"\bCrossy\b", "Android 첫 판에 넣지 않는다(G §8-18 #7)", "Crossy Aing"),
    ("crossy-ko", r"길\s?건너", "Android 첫 판에 넣지 않는다(G §8-18 #7)", "길건너 아잉이"),
    ("all-time", r"all-time", "역대 순위는 Android 첫 판에 넣지 않는다(G §8-18 #7)", "all-time ranking"),
    ("all-time-ko", r"역대", "역대 순위는 Android 첫 판에 넣지 않는다(G §8-18 #7)", "오늘·역대 순위"),
    ("challenge-mission", r"도전\s*미션", "iOS 1.0.13 에서 「누적 미션」으로 바뀐 옛 이름이다", "「도전 미션」"),
]
STALE_RES = [(i, re.compile(p, re.I), why, sample) for i, p, why, sample in STALE_RULES]

# ② 칸마다 꼭 있어야 하는 문구(칸이 비거나 줄어든 것, 약속이 빠진 것을 잡는다).
REQUIRED_PHRASES = {
    "full_description": [
        "aing-check.vercel.app/delete-account",
        "현금으로 사거나 바꿀 수 없",
        "다른 사람에게 보낼 수도 없",
        "확률은 앱 안에 공개",
    ],
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

# ── ③ 설계 E 의 표(원문 글자) ─────────────────────────────────────────────────────────────────
# E §9.5 (Play 항목 · 수집 · 필수/선택 · 목적). 공유 열은 이 문서가 더했다 — 전부 '아니오' 또는 '—'.
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

# E §9.3 (항목 · 초안 답) — 답 칸 원문 그대로(굵게 표시와 공백만 정규화해 비교한다).
E_IARC = [
    ("앱 범주", '게임이 아닌 "기타(생산성·커뮤니케이션)"'),
    ("폭력·공포·성적·언어·약물·저속한 유머", "없음"),
    ("실제 도박", "아니오"),
    ("모의 도박", "**예(추천)** — 루비(판매·환금 없음)로 오목·체스·테트리스 판돈 3/5/10, 수수료 10%"),
    ("사용자 상호작용(메시지·채팅·UGC)", "예"),
    ("위치 공유", "아니오"),
    ("디지털 상품 구매", "아니오"),
    ("무작위 아이템", '질문이 "**돈으로** 산" 을 조건으로 하면 아니오, "가상 화폐 포함"이면 예 — 원문을 보고 고른다'),
    ("무제한 웹 접근", "아니오"),
]
# E 원문에서 문서가 일부러 뺀 글자: 항목 → (뺀 글자, 이유). 답(판정)은 바꾸지 않는 것만 여기 둔다.
E_IARC_EDITS = {
    "모의 도박": (", 수수료 10%", "2026-10-22 duel_fee_off 로 대결 수수료가 없어졌다 — 답 '예'는 그대로, 확률·비율 숫자 0 규칙(①)과도 맞는다"),
}


def _norm(cell):
    return re.sub(r"\s+", " ", cell.replace("**", "")).strip()


def _plain(cell):
    return cell.replace("**", "").strip()


def iarc_expected():
    """E 원문 답에 E_IARC_EDITS 를 적용한 기대 답(정규화)."""
    out = []
    for item, answer in E_IARC:
        edit = E_IARC_EDITS.get(item)
        if edit is not None:
            answer = answer.replace(edit[0], "", 1)
        out.append((item, _norm(answer)))
    return out


def _cells(line):
    return [c.strip() for c in line.strip().strip("|").split("|")]


def _section_rows(text, heading_re):
    """heading_re 에 맞는 제목 줄 아래 첫 표의 본문 행(머리·구분 줄 뺌)을 칸 목록으로 돌려준다."""
    lines = text.splitlines()
    start = None
    level = None
    for i, line in enumerate(lines):
        m = re.match(r"(#+) ", line)
        if m and re.match(heading_re, line[m.end():]):
            start = i + 1
            level = len(m.group(1))
            break
    if start is None:
        return None
    rows = []
    in_table = False
    for line in lines[start:]:
        m = re.match(r"(#+) ", line)
        if m and len(m.group(1)) <= level:
            break
        if line.startswith("|"):
            in_table = True
            rows.append(line)
        elif in_table:
            break
    return [_cells(r) for r in rows[2:]]  # 머리 줄과 구분 줄을 뺀다


def parse_fields(text):
    found = {}
    for m in FIELD_RE.finditer(text):
        found[m.group(1)] = (int(m.group(2)), m.group(3))
    return found


def check(docs):
    """문서 폴더를 잰다. 돌려주는 실패는 (종류, 열쇠, 설명) — self-test 는 (종류, 열쇠)로 어느 규칙이 잡았는지 본다."""
    docs = pathlib.Path(docs)
    fails = []
    texts = {}
    for name in REQUIRED_FILES:
        p = docs / name
        if not p.is_file():
            fails.append(("files", name, "없는 파일: %s" % name))
        else:
            texts[name] = p.read_text(encoding="utf-8")
    md_files = sorted(p for p in docs.rglob("*.md") if "_check" not in p.relative_to(docs).parts)
    for p in md_files:
        rel = str(p.relative_to(docs))
        text = texts.get(rel) if rel in texts else p.read_text(encoding="utf-8")
        for n, line in enumerate(text.splitlines(), 1):
            for rid, hit, what, _ in ODDS_RULES:
                if hit(line):
                    fails.append(("odds", rid, "%s:%d %s" % (rel, n, what)))
            for rid, rx, what, _ in PRIVACY_RES:
                if rx.search(line):
                    fails.append(("privacy", rid, "%s:%d %s" % (rel, n, what)))

    fields = {}
    for name, wanted in FIELDS_BY_FILE.items():
        text = texts.get(name)
        if text is None:
            continue
        found = parse_fields(text)
        for key in wanted:
            if key not in found:
                fails.append(("fields", "missing:" + key, "%s: 칸 표식 없음 '%s'" % (name, key)))
                continue
            marker_limit, body = found[key]
            if marker_limit != FIELD_LIMITS[key]:
                fails.append(("limit", "marker:" + key,
                              "%s: '%s' 표식 한도 %d ≠ 계약 %d" % (name, key, marker_limit, FIELD_LIMITS[key])))
            if len(body) > FIELD_LIMITS[key]:
                fails.append(("limit", "length:" + key, "%s: '%s' %d자 > %d" % (name, key, len(body), FIELD_LIMITS[key])))
            if not body.strip():
                fails.append(("fields", "empty:" + key, "%s: '%s' 가 비었다" % (name, key)))
            fields[key] = body

    for key, body in fields.items():
        for rid, rx, why, _ in STALE_RES:
            m = rx.search(body)
            if m:
                fails.append(("stale", "%s@%s" % (rid, key), "%s: 낡은 문구 '%s' — %s" % (key, m.group(0), why)))
        for phrase in REQUIRED_PHRASES.get(key, []):
            if phrase not in body:
                fails.append(("required", "%s:%s" % (key, phrase), "%s: 꼭 있어야 할 문구 없음 '%s'" % (key, phrase)))

    ds = texts.get("data-safety.md")
    if ds is not None:
        rows = _section_rows(ds, r"2\.")
        if rows is None:
            fails.append(("data-safety", "section", "data-safety.md: '## 2.' 절이 없다"))
        else:
            if any(len(r) < 5 for r in rows):
                fails.append(("data-safety", "cells", "data-safety.md §2: 칸이 모자란 행이 있다"))
            got = [(_plain(r[0]), _plain(r[1]), _plain(r[3]), _plain(r[4]), _plain(r[2])) for r in rows if len(r) >= 5]
            have = [g[:4] for g in got]
            if have != E_DATA_SAFETY:
                before = len(fails)
                for miss in [w for w in E_DATA_SAFETY if w not in have]:
                    fails.append(("data-safety", "rows", "E §9.5 와 다름 — 없거나 바뀐 행: %s" % " | ".join(miss)))
                for extra in [h for h in have if h not in E_DATA_SAFETY]:
                    fails.append(("data-safety", "rows", "E §9.5 에 없는 행: %s" % " | ".join(extra)))
                if len(fails) == before:
                    fails.append(("data-safety", "rows", "E §9.5 와 행 순서나 개수가 다르다"))
            for g in got:
                if g[4] not in ("아니오", "—"):
                    fails.append(("data-safety", "share",
                                  "공유 열은 '아니오'(서비스 제공자만) 또는 '—' 여야 한다: %s → %s" % (g[0], g[4])))

    cr = texts.get("content-rating.md")
    if cr is not None:
        rows = _section_rows(cr, r"2\.")
        if rows is None:
            fails.append(("iarc", "section", "content-rating.md: '## 2.' 절이 없다"))
        else:
            got = [(_plain(r[0]), _norm(r[1])) for r in rows if len(r) >= 2]
            names = [g[0] for g in got]
            if names != [e[0] for e in E_IARC]:
                fails.append(("iarc", "names", "E §9.3 과 항목 목록이 다르다: %s" % " / ".join(names)))
            answers = dict(got)
            for item, want in iarc_expected():
                ans = answers.get(item)
                if ans is not None and ans != want:
                    fails.append(("iarc", "answer:" + item, "E §9.3 과 답이 다르다: %s → '%s' (기대 '%s')" % (item, ans, want)))
    return fails, fields


def check_e_source(text):
    """설계 E 마크다운의 §9.5·§9.3 표가 이 파일의 기대값과 같은지 잰다."""
    fails = []
    ds = _section_rows(text, r"9\.5\b")
    if ds is None:
        fails.append(("e-source", "section", "E: '### 9.5' 절이 없다"))
    else:
        got = [tuple(_plain(c) for c in r[:4]) for r in ds]
        if got != E_DATA_SAFETY:
            for i, (g, w) in enumerate(zip(got + [None] * len(E_DATA_SAFETY), E_DATA_SAFETY + [None] * len(got))):
                if g != w:
                    fails.append(("e-source", "data-safety", "E §9.5 %d행: E=%s · 검사기=%s" % (i + 1, g, w)))
                    break
    ia = _section_rows(text, r"9\.3\b")
    if ia is None:
        fails.append(("e-source", "section", "E: '### 9.3' 절이 없다"))
    else:
        got = [(_plain(r[0]), _norm(r[1])) for r in ia if len(r) >= 2]
        want = [(item, _norm(ans)) for item, ans in E_IARC]
        if got != want:
            for g, w in zip(got + [None] * len(want), want + [None] * len(got)):
                if g != w:
                    fails.append(("e-source", "iarc", "E §9.3: E=%s · 검사기=%s" % (g, w)))
                    break
    return fails


# ── self-test ────────────────────────────────────────────────────────────────────────────────
# 규칙 이름 목록을 따로 고정한다. 규칙을 지우면 여기와 어긋나 빨갛다(규칙과 이 목록은 같은 커밋에서 고친다).
SELF_TEST_PINS = {
    "odds": ["pct-sign", "pct-word-ko", "pct-word-en", "pct-pro", "n-in-m-ko", "fraction-ko", "n-in-m-en",
             "decimal-fraction", "odds-sentence"],
    "privacy": ["email", "long-number", "home-path", "secret-store", "jwt", "service-role", "anthropic-key",
                "google-key", "github-token", "private-key", "supabase-host", "firebase-config", "signing-key",
                "phone-number"],
    "stale": ["mac-only-possible", "mac-only-in", "mac-only-done", "mac-only-en", "mac-only-ko", "two-games-en",
              "two-games-ko",
              "iphone", "ios", "apns", "app-store", "testflight", "guideline", "new-in", "phone-login",
              "already-achieved", "turns-achieved", "cred-template", "fee-en", "fee-ko", "crossy", "crossy-ko",
              "all-time", "all-time-ko", "challenge-mission"],
    "required": [
        ("full_description", "aing-check.vercel.app/delete-account"),
        ("full_description", "현금으로 사거나 바꿀 수 없"),
        ("full_description", "다른 사람에게 보낼 수도 없"),
        ("full_description", "확률은 앱 안에 공개"),
        ("review_notes_short", "aing-check.vercel.app/delete-account"),
        ("review_notes_short", "cannot be bought"),
        ("review_notes_short", "isolated"),
        ("review_notes_long", "aing-check.vercel.app/delete-account"),
        ("review_notes_long", "cannot be bought"),
        ("review_notes_long", "Report"),
        ("review_notes_long", "Block"),
        ("review_notes_long", "simulated gambling"),
        ("review_notes_long", "Show odds"),
        ("review_notes_long", "isolated"),
    ],
}
SELF_TEST_FILES = ["README.md", "store-listing.md", "data-safety.md", "content-rating.md", "app-access.md", "app-content.md"]
SELF_TEST_FIELDS = {
    "title": "store-listing.md",
    "short_description": "store-listing.md",
    "full_description": "store-listing.md",
    "release_notes": "store-listing.md",
    "review_notes_short": "app-access.md",
    "review_notes_long": "app-access.md",
}

# ③ 결함: (이름, 파일, 찾을 글자, 바꿀 글자, 기대 (종류, 열쇠)). 찾을 글자는 원본에 정확히 한 번 있어야 한다.
TABLE_MUTATIONS = [
    ("ds-item", "data-safety.md", "| 개인 정보 › 사용자 ID |", "| 개인 정보 › 기타 정보 |", ("data-safety", "rows")),
    ("ds-collect", "data-safety.md", "| 개인 정보 › 이메일 주소 | 예 |", "| 개인 정보 › 이메일 주소 | 아니오 |", ("data-safety", "rows")),
    ("ds-required", "data-safety.md", "| 사진 및 동영상 › 사진 | 예 | 아니오 | 선택 |", "| 사진 및 동영상 › 사진 | 예 | 아니오 | 필수 |",
     ("data-safety", "rows")),
    ("ds-purpose", "data-safety.md", "| 개인 정보 › 사용자 ID | 예 | 아니오 | 필수 | 계정 관리 |",
     "| 개인 정보 › 사용자 ID | 예 | 아니오 | 필수 | 앱 기능 |", ("data-safety", "rows")),
    ("ds-extra-row", "data-safety.md", "| 보안: 전송 중 암호화 |",
     "| 개인 정보 › 기타 정보 | 예 | 아니오 | 필수 | 앱 기능 | 소속 센터 |\n| 보안: 전송 중 암호화 |", ("data-safety", "rows")),
    ("ds-share", "data-safety.md", "| 메시지 › 기타 인앱 메시지 | 예 | 아니오 |", "| 메시지 › 기타 인앱 메시지 | 예 | 예 |", ("data-safety", "share")),
    ("ds-section", "data-safety.md", "## 2. 항목별 답", "## 둘. 항목별 답", ("data-safety", "section")),
    ("iarc-drop-row", "content-rating.md", "| 위치 공유 | 아니오 | 위치 코드·권한 없음 |\n", "", ("iarc", "names")),
    ("iarc-section", "content-rating.md", "## 2. 답", "## 둘. 답", ("iarc", "section")),
]
# 행을 지우거나 순서를 바꾸는 결함(찾을 글자 대신 줄 단위로 다룬다).
ROW_MUTATIONS = [
    ("ds-drop-row", "data-safety.md", "| 보안: 삭제 요청 수단 |", "drop", ("data-safety", "rows")),
    ("ds-swap-rows", "data-safety.md", "| 보안: 삭제 요청 수단 |", "swap-up", ("data-safety", "rows")),
]
# IARC 항목마다 뜻을 뒤집은 답(문서 §2 표의 둘째 칸을 통째로 바꾼다).
IARC_FLIPS = [
    ("앱 범주", '"기타(생산성·커뮤니케이션)"가 아닌 게임'),
    ("앱 범주", '게임이 아닌 "기타(생산성·커뮤니케이션)"가 아니라 게임'),
    ("폭력·공포·성적·언어·약물·저속한 유머", "만화 폭력"),
    ("실제 도박", "예"),
    ("모의 도박", "**아니오** — 루비(판매·환금 없음)로 오목·체스·테트리스 판돈 3/5/10"),
    ("사용자 상호작용(메시지·채팅·UGC)", "아니오"),
    ("위치 공유", "예"),
    ("디지털 상품 구매", "예"),
    ("무작위 아이템", '질문이 "**돈으로** 산" 을 조건으로 하면 예, "가상 화폐 포함"이면 아니오 — 원문을 보고 고른다'),
    ("무작위 아이템", '질문이 "**돈으로** 산" 을 조건으로 하면 아니오, "가상 화폐 포함"이면 예 — 원문을 보고 고른다 — 무조건 \'예\''),
    ("무제한 웹 접근", "예"),
]


def _field_span(text, key):
    m = re.search(r"<!--\s*field:\s*%s\s*·\s*최대\s*\d+자\s*-->\s*\n```text\n(.*?)\n```" % re.escape(key), text, re.S)
    return (m.start(1), m.end(1)) if m else None


def _build_mutations():
    """(이름, 사본을 바꾸는 함수, 기대 (종류, 열쇠)) 목록."""
    muts = []

    def append_line(name, line):
        def fn(d):
            p = d / name
            p.write_text(p.read_text(encoding="utf-8") + "\n" + line + "\n", encoding="utf-8")
        return fn

    def field_edit(key, how):
        def fn(d):
            p = d / SELF_TEST_FIELDS[key]
            text = p.read_text(encoding="utf-8")
            span = _field_span(text, key)
            if span is None:
                raise LookupError("칸 '%s' 없음" % key)
            s, e = span
            p.write_text(text[:s] + how(text[s:e]) + text[e:], encoding="utf-8")
        return fn

    def marker_edit(key, how):
        def fn(d):
            p = d / SELF_TEST_FIELDS[key]
            text = p.read_text(encoding="utf-8")
            m = re.search(r"<!--\s*field:\s*%s\s*·\s*최대\s*(\d+)자\s*-->\n" % re.escape(key), text)
            if m is None:
                raise LookupError("칸 표식 '%s' 없음" % key)
            p.write_text(text[:m.start()] + how(m) + text[m.end():], encoding="utf-8")
        return fn

    def replace_once(name, old, new):
        def fn(d):
            p = d / name
            text = p.read_text(encoding="utf-8")
            if text.count(old) != 1:
                raise LookupError("'%s' 가 %s 에 %d번 있다(1번이어야 한다)" % (old[:30], name, text.count(old)))
            p.write_text(text.replace(old, new), encoding="utf-8")
        return fn

    def row_edit(name, marker, how):
        def fn(d):
            p = d / name
            lines = p.read_text(encoding="utf-8").split("\n")
            idx = [i for i, l in enumerate(lines) if l.startswith(marker)]
            if len(idx) != 1:
                raise LookupError("'%s' 행이 %d개" % (marker, len(idx)))
            i = idx[0]
            if how == "drop":
                del lines[i]
            else:
                lines[i - 1], lines[i] = lines[i], lines[i - 1]
            p.write_text("\n".join(lines), encoding="utf-8")
        return fn

    def iarc_flip(item, answer):
        def fn(d):
            p = d / "content-rating.md"
            lines = p.read_text(encoding="utf-8").split("\n")
            idx = [i for i, l in enumerate(lines) if l.startswith("| %s |" % item)]
            if len(idx) != 1:
                raise LookupError("IARC 행 '%s' 가 %d개" % (item, len(idx)))
            cells = _cells(lines[idx[0]])
            cells[1] = answer
            lines[idx[0]] = "| " + " | ".join(cells) + " |"
            p.write_text("\n".join(lines), encoding="utf-8")
        return fn

    def delete_file(name):
        def fn(d):
            (d / name).unlink()
        return fn

    files = SELF_TEST_FILES
    for i, (rid, _, _, sample) in enumerate(ODDS_RULES):
        muts.append(("odds:%s" % rid, append_line(files[i % len(files)], sample), ("odds", rid)))
    for i, (rid, _, _, sample) in enumerate(PRIVACY_RULES):
        muts.append(("privacy:%s" % rid, append_line(files[(i + 3) % len(files)], sample), ("privacy", rid)))
    keys = list(SELF_TEST_FIELDS)
    for i, (rid, _, _, sample) in enumerate(STALE_RULES):
        key = keys[i % len(keys)]
        muts.append(("stale:%s@%s" % (rid, key), field_edit(key, lambda b, s=sample: b + " " + s), ("stale", "%s@%s" % (rid, key))))
    for key, phrase in SELF_TEST_PINS["required"]:
        muts.append(("required:%s:%s" % (key, phrase), field_edit(key, lambda b, ph=phrase: b.replace(ph, "▢")),
                     ("required", "%s:%s" % (key, phrase))))
    for key in keys:
        limit = FIELD_LIMITS.get(key, 0)
        muts.append(("missing:" + key, marker_edit(key, lambda m: ""), ("fields", "missing:" + key)))
        muts.append(("marker:" + key, marker_edit(key, lambda m: m.group(0).replace("최대 %s자" % m.group(1), "최대 %d자" % (int(m.group(1)) + 7))),
                     ("limit", "marker:" + key)))
        muts.append(("length:" + key, field_edit(key, lambda b, n=limit: b + "가" * max(1, n + 1 - len(b))), ("limit", "length:" + key)))
        muts.append(("empty:" + key, field_edit(key, lambda b: ""), ("fields", "empty:" + key)))
    for name in files:
        muts.append(("files:" + name, delete_file(name), ("files", name)))
    for label, name, old, new, expect in TABLE_MUTATIONS:
        muts.append((label, replace_once(name, old, new), expect))
    for label, name, marker, how, expect in ROW_MUTATIONS:
        muts.append((label, row_edit(name, marker, how), expect))
    for item, answer in IARC_FLIPS:
        muts.append(("iarc-flip:%s→%s" % (item, answer[:16]), iarc_flip(item, answer), ("iarc", "answer:" + item)))
    return muts


def _synthetic_e():
    lines = ["# E", "", "### 9.3 IARC", "", "| 항목(예상) | 초안 답 | 근거 |", "|---|---|---|"]
    lines += ["| %s | %s | 근거 |" % (item, ans) for item, ans in E_IARC]
    lines += ["", "### 9.4 다른 절", "", "### 9.5 Data safety 초안", "",
              "| Play 항목 | 수집 | 필수/선택 | 목적 | 내용·근거 |", "|---|---|---|---|---|"]
    lines += ["| %s | %s | %s | %s | 근거 |" % row for row in E_DATA_SAFETY]
    lines += ["", "### 9.6 다음 절", ""]
    return "\n".join(lines)


def self_test():
    problems = []
    for fam, rules in (("odds", ODDS_RULES), ("privacy", PRIVACY_RULES), ("stale", STALE_RULES)):
        ids = [r[0] for r in rules]
        if ids != SELF_TEST_PINS[fam]:
            problems.append("%s 규칙 목록이 고정 목록과 다르다: 빠짐 %s · 더함 %s" % (
                fam, sorted(set(SELF_TEST_PINS[fam]) - set(ids)), sorted(set(ids) - set(SELF_TEST_PINS[fam]))))
    req = [(k, p) for k, ps in REQUIRED_PHRASES.items() for p in ps]
    if sorted(req) != sorted(SELF_TEST_PINS["required"]):
        problems.append("꼭 있어야 할 문구 목록이 고정 목록과 다르다: 빠짐 %s · 더함 %s" % (
            sorted(set(SELF_TEST_PINS["required"]) - set(req)), sorted(set(req) - set(SELF_TEST_PINS["required"]))))
    if sorted(k for ks in FIELDS_BY_FILE.values() for k in ks) != sorted(SELF_TEST_FIELDS):
        problems.append("콘솔 칸 목록이 고정 목록과 다르다: %s" % FIELDS_BY_FILE)
    if REQUIRED_FILES != SELF_TEST_FILES:
        problems.append("필수 파일 목록이 고정 목록과 다르다: %s" % REQUIRED_FILES)

    muts = _build_mutations()
    with tempfile.TemporaryDirectory(prefix="w6c-listing-") as tmp:
        base = pathlib.Path(tmp) / "pristine"
        shutil.copytree(DEFAULT_DOCS, base, ignore=shutil.ignore_patterns("_check", "__pycache__"))
        fails, _ = check(base)
        if fails:
            problems.append("원본이 이미 빨갛다: %s" % [f[2] for f in fails[:3]])
        for i, (label, fn, expect) in enumerate(muts):
            copy = pathlib.Path(tmp) / ("m%03d" % i)
            shutil.copytree(base, copy)
            try:
                fn(copy)
            except LookupError as e:
                problems.append("결함 %03d(%s): 심을 자리 없음 — %s" % (i, label, e))
                continue
            got, _ = check(copy)
            keys = set((k, key) for k, key, _ in got)
            if expect not in keys:
                problems.append("결함 %03d(%s) 이 %s 로 빨개지지 않았다 — 나온 것 %s" % (
                    i, label, "/".join(expect), sorted(keys)[:6]))
            shutil.rmtree(copy)

    # --e-source 비교기: 기대값으로 지은 E 는 초록, 칸 하나를 바꾼 E 는 빨강.
    e_text = _synthetic_e()
    e_cases = [
        ("e-pristine", e_text, None),
        ("e-ds-cell", e_text.replace("| 개인 정보 › 사용자 ID | 예 | 필수 | 계정 관리 |", "| 개인 정보 › 사용자 ID | 예 | 선택 | 계정 관리 |", 1),
         ("e-source", "data-safety")),
        ("e-iarc-cell", e_text.replace("| 위치 공유 | 아니오 |", "| 위치 공유 | 예 |", 1), ("e-source", "iarc")),
        ("e-no-section", e_text.replace("### 9.5 Data safety", "### 아홉 Data safety", 1), ("e-source", "section")),
    ]
    for label, text, expect in e_cases:
        keys = set((k, key) for k, key, _ in check_e_source(text))
        if expect is None and keys:
            problems.append("%s: 기대값으로 지은 E 가 빨갛다 %s" % (label, sorted(keys)))
        if expect is not None and (text == e_text or expect not in keys):
            problems.append("%s: %s 로 빨개지지 않았다 — 나온 것 %s" % (label, "/".join(expect), sorted(keys)))

    total = len(muts) + len(e_cases) - 1
    if problems:
        for p in problems:
            print("self-test: FAIL %s" % p)
        print("self-test: 결함 %d · 실패 %d" % (total, len(problems)))
        return 1
    print("self-test: 원본 초록 · 고정 목록 일치(odds %d · privacy %d · stale %d · required %d · 칸 %d · 파일 %d) · "
          "결함 %d/%d 전부 그 규칙으로 빨강" % (
              len(ODDS_RULES), len(PRIVACY_RULES), len(STALE_RULES), len(req), len(SELF_TEST_FIELDS),
              len(SELF_TEST_FILES), total, total))
    return 0


def main(argv=None):
    ap = argparse.ArgumentParser(description="docs/android 초안 검사기(W6-c)")
    ap.add_argument("--docs", default=str(DEFAULT_DOCS))
    ap.add_argument("--self-test", action="store_true")
    ap.add_argument("--e-source", help="설계 E 마크다운(E-android-platform.md) — 기대값이 원문 표와 같은지 함께 잰다")
    args = ap.parse_args(argv)
    if args.self_test:
        return self_test()
    fails, fields = check(args.docs)
    if args.e_source:
        fails += check_e_source(pathlib.Path(args.e_source).read_text(encoding="utf-8"))
    for kind, key, msg in fails:
        print("check_listing: FAIL [%s %s] %s" % (kind, key, msg))
    lens = " ".join("%s=%d/%d" % (k, len(fields[k]), FIELD_LIMITS[k]) for k in FIELD_LIMITS if k in fields)
    print("check_listing: files=%d fields=%d %s e-source=%s failures=%d" % (
        len(REQUIRED_FILES), len(fields), lens, "checked" if args.e_source else "skipped", len(fails)))
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
