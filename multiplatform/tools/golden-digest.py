#!/usr/bin/env python3
"""골든 신선도 셋째 겹(C§5.4 ③, W0-b) — Swift 없는 CI 가 "맥에서 골든을 다시 돌려야 하는가"를 안다.

  python3 -I multiplatform/tools/golden-digest.py --check      _digests.json 을 다시 셈해 비교(CI 의 golden-digest 잡 · gate-fast)
  python3 -I multiplatform/tools/golden-digest.py --write      _digests.json 을 다시 쓴다(scripts/golden-export.sh 쓰기 모드가 부른다)
  python3 -I multiplatform/tools/golden-digest.py assemble --run DIR --mode compare|write --export-tests N
                                                               영수증(DIR/receipts) → _manifest.json 조립 · 고아 검사
  python3 -I multiplatform/tools/golden-digest.py --self-test  결함을 심은 사본으로 빨강을 확인

지문(_digests.json): 계약 골든(_manifest.json 의 goldens)마다
  · file          골든 파일 바이트의 sha256(손으로 고친 골든을 잡는다). 줄 끝 CRLF 는 LF 로 접어 센다 —
                  Windows 체크아웃(core.autocrlf=true)이 글자 파일을 CRLF 로 풀어 놓아도 같은 지문이다.
                  값의 대조는 Kotlin 이 파싱해서 하므로(Golden.load) 줄 끝은 계약이 아니다.
  · generator     생성 시험 Swift 파일의 주석 걷은 sha256
  · swiftSources  원본 Swift 파일마다 주석 걷은 sha256(엔진만 고친 main 커밋도 잡는다 — §8-10)
  · support       작성기(Tests/CheckGoldenSupport/*.swift)와 골든 갈래가 같이 쓰는 바탕
                  (Tests/*/GoldenExport/_base/*.swift — 테트리스 연산 재생 GoldenTetrisOps 등)의 주석 걷은 sha256 — 모든 골든에 공통
주석 걷기는 swift_source.py 한 벌(C§5.4 "Python 한 벌"). 주석·빈 줄만 바꾼 커밋은 지문이 그대로다.
실험 표(probes)는 지문에 넣지 않는다 — 계약이 아니고, 맥 비교 모드가 지킨다.

--check 는 지문 말고 생성 시험도 본다(계약·실험 표 모두): 생성 시험 파일이 `Tests/<타깃>/GoldenExport/` 아래 있고,
그 코드(주석 밖)에 골든 이름이 **글자 리터럴 그대로**(`golden: "rng/splitmix64"`) 있어야 한다. 주석 걷기가 Python 한 벌이라
이 판정도 여기 있다(Swift 정적 잠금은 파일 집합만 본다).

정규 JSON = json.dumps(값, indent=2, sort_keys=True, ensure_ascii=False) + "\\n" (Swift GoldenJSON.canonicalText 와 바이트가 같다).
종료 코드: 0 일치 · 1 불일치/문제 · 2 사용법·파일 없음.
"""
from __future__ import annotations

import argparse
import glob
import hashlib
import io
import json
import os
import re
import shutil
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)  # -I 는 스크립트 폴더를 빼므로 같은 폴더의 swift_source 를 명시적으로 넣는다
sys.dont_write_bytecode = True  # 저장소에 __pycache__ 를 흘리지 않는다(기억 agents-leak-files-into-repo)
import swift_source  # noqa: E402

REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
CONTRACT_DIR = "contract/golden"
PROBE_DIR = "multiplatform/testkit/src/desktopTest/resources/golden"
SUPPORT_DIR = "Tests/CheckGoldenSupport"
# 지문 support 에 드는 Swift 파일(모든 골든 공통). 둘째는 골든 갈래가 그대로 쓰는 공용 바탕(_base — W0-b 소유).
SUPPORT_GLOBS = (f"{SUPPORT_DIR}/*.swift", "Tests/*/GoldenExport/_base/*.swift")
GENERATOR_PREFIX = re.compile(r"^Tests/[^/]+/GoldenExport/")
STRIP_RULE = ("swift_source.strip_comments v1 — 주석·빈 줄·줄 끝 공백을 뺀 UTF-8 의 sha256 · "
              "골든 파일(file)은 줄 끝 CRLF 를 LF 로 접은 바이트의 sha256")
MANIFEST = f"{CONTRACT_DIR}/_manifest.json"
DIGESTS = f"{CONTRACT_DIR}/_digests.json"
TOTAL_BUDGET = 10 * 1024 * 1024
RERUN = "맥에서 scripts/golden-export.sh 를 돌려라(엔진이 바뀌었으면 CHECK_GOLDEN_WRITE=1 로 다시 쓰고 Kotlin 을 따라 고친다)"


def canonical(value) -> str:
    return json.dumps(value, indent=2, sort_keys=True, ensure_ascii=False) + "\n"


def read_bytes(repo: str, rel: str) -> bytes:
    with open(os.path.join(repo, rel), "rb") as f:
        return f.read()


def read_text(repo: str, rel: str) -> str:
    return read_bytes(repo, rel).decode("utf-8")


def json_files(repo: str, rel_dir: str) -> set[str]:
    base = os.path.join(repo, rel_dir)
    found: set[str] = set()
    for dirpath, _dirs, files in os.walk(base):
        for name in files:
            if name.endswith(".json"):
                found.add(os.path.relpath(os.path.join(dirpath, name), repo).replace(os.sep, "/"))
    return found


def contract_files(repo: str) -> set[str]:
    return {p for p in json_files(repo, CONTRACT_DIR) if p not in (MANIFEST, DIGESTS)}


def support_files(repo: str) -> list[str]:
    found: set[str] = set()
    for pattern in SUPPORT_GLOBS:
        for path in glob.glob(os.path.join(repo, pattern)):
            if os.path.isfile(path):
                found.add(os.path.relpath(path, repo).replace(os.sep, "/"))
    return sorted(found)


def file_digest(data: bytes) -> str:
    """골든 파일 지문. CRLF → LF 로 접는다(Windows 러너 체크아웃 — 저장소에 .gitattributes 가 없다)."""
    return hashlib.sha256(data.replace(b"\r\n", b"\n")).hexdigest()


def compute_digests(repo: str, manifest: dict) -> dict:
    support = {rel: swift_source.stripped_sha256(read_text(repo, rel)) for rel in support_files(repo)}
    goldens = {}
    for entry in manifest.get("goldens", []):
        name = entry["golden"]
        goldens[name] = {
            "file": file_digest(read_bytes(repo, entry["path"])),
            "generator": {entry["generator"]: swift_source.stripped_sha256(read_text(repo, entry["generator"]))},
            "swiftSources": {src: swift_source.stripped_sha256(read_text(repo, src)) for src in entry["swiftSources"]},
        }
    return {
        "schema": 1,
        "strip": STRIP_RULE,
        "support": support,
        "goldens": goldens,
    }


def generator_problems(repo: str, manifest: dict) -> list[str]:
    """생성 시험 판정(계약·실험 표): GoldenExport 폴더 안 · 파일 있음 · 코드(주석 밖)에 이름 글자 리터럴."""
    problems: list[str] = []
    for key, label in (("goldens", "계약"), ("probes", "실험 표")):
        for entry in manifest.get(key, []):
            name, gen = entry.get("golden"), entry.get("generator")
            if not isinstance(name, str) or not isinstance(gen, str):
                problems.append(f"{label}: golden·generator 칸이 빠진 항목 {entry!r}")
                continue
            if not GENERATOR_PREFIX.match(gen):
                problems.append(f"{label} {name}: 생성 시험 {gen} 이 Tests/<타깃>/GoldenExport/ 밖이다")
            if not os.path.isfile(os.path.join(repo, gen)):
                problems.append(f"{label} {name}: 생성 시험 {gen} 가 없다")
                continue
            literal = f'"{name}"'
            if not any(seg.kind == "string" and seg.text == literal for seg in swift_source.segments(read_text(repo, gen))):
                problems.append(f"{label} {name}: 생성 시험 {gen} 의 코드(주석 밖)에 글자 리터럴 {literal} 이 없다 "
                                f"(지운 생성 시험의 이름이 주석에만 남았나?)")
    return problems


def diff_digests(want: dict, have: dict) -> list[str]:
    problems: list[str] = []
    for key in ("schema", "strip"):
        if want.get(key) != have.get(key):
            problems.append(f"{key}: 기록 {have.get(key)!r} ≠ 지금 {want.get(key)!r}")
    for rel in sorted(set(want.get("support", {})) | set(have.get("support", {}))):
        w, h = want.get("support", {}).get(rel), have.get("support", {}).get(rel)
        if w != h:
            problems.append(f"작성기·바탕 {rel}: 기록 {str(h)[:12]} ≠ 지금 {str(w)[:12]}")
    wg, hg = want.get("goldens", {}), have.get("goldens", {})
    for name in sorted(set(wg) | set(hg)):
        if name not in hg:
            problems.append(f"골든 {name}: _digests.json 에 없다")
            continue
        if name not in wg:
            problems.append(f"골든 {name}: _manifest.json 에 없는데 지문만 남았다")
            continue
        w, h = wg[name], hg[name]
        if w["file"] != h.get("file"):
            problems.append(f"골든 {name}: 파일 바이트가 마지막 내보내기와 다르다(손으로 고쳤나?)")
        for group in ("generator", "swiftSources"):
            for rel in sorted(set(w[group]) | set(h.get(group, {}))):
                if w[group].get(rel) != h.get(group, {}).get(rel):
                    problems.append(f"골든 {name}: {group} {rel} 이 바뀌었다")
    return problems


def load_manifest(repo: str) -> dict:
    path = os.path.join(repo, MANIFEST)
    if not os.path.isfile(path):
        raise FileNotFoundError(f"{MANIFEST} 가 없다 — CHECK_GOLDEN_WRITE=1 scripts/golden-export.sh 로 만든다")
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def cmd_check(repo: str) -> int:
    try:
        manifest = load_manifest(repo)
        with open(os.path.join(repo, DIGESTS), encoding="utf-8") as f:
            recorded_text = f.read()
    except (FileNotFoundError, OSError) as e:
        print(f"golden-digest: {e}", file=sys.stderr)
        return 2
    recorded = json.loads(recorded_text)
    want = compute_digests(repo, manifest)
    problems = diff_digests(want, recorded)
    if recorded_text != canonical(recorded):
        problems.append("_digests.json 이 정규 형식이 아니다(손으로 고쳤나?)")
    missing = contract_files(repo) - {e["path"] for e in manifest.get("goldens", [])}
    for rel in sorted(missing):
        problems.append(f"{rel}: _manifest.json 에 없는 골든 파일(고아)")
    problems += generator_problems(repo, manifest)
    if problems:
        print(f"golden-digest --check: 불일치 {len(problems)}건 — {RERUN}", file=sys.stderr)
        for p in problems:
            print(f"  - {p}", file=sys.stderr)
        return 1
    print(f"golden-digest --check: 일치 — 골든 {len(want['goldens'])} · 작성기·바탕 파일 {len(want['support'])} · "
          f"생성 시험 이름 {len(manifest.get('goldens', [])) + len(manifest.get('probes', []))}")
    return 0


def cmd_write(repo: str) -> int:
    try:
        manifest = load_manifest(repo)
    except FileNotFoundError as e:
        print(f"golden-digest: {e}", file=sys.stderr)
        return 2
    digests = compute_digests(repo, manifest)
    with open(os.path.join(repo, DIGESTS), "w", encoding="utf-8") as f:
        f.write(canonical(digests))
    print(f"golden-digest --write: {DIGESTS} — 골든 {len(digests['goldens'])}")
    return 0


def cmd_assemble(repo: str, run_dir: str, mode: str, export_tests: int) -> int:
    receipts_dir = os.path.join(run_dir, "receipts")
    receipts = []
    if os.path.isdir(receipts_dir):
        for name in sorted(os.listdir(receipts_dir)):
            if name.endswith(".json"):
                with open(os.path.join(receipts_dir, name), encoding="utf-8") as f:
                    receipts.append(json.load(f))
    problems: list[str] = []
    want_status = "same" if mode == "compare" else "written"
    for r in receipts:
        if r["status"] != want_status:
            problems.append(f"{r['path']}: 상태 {r['status']}(기대 {want_status}) — 생성 시험 {r['generator']}")
    produced = {r["path"] for r in receipts}
    for rel in sorted(contract_files(repo) - produced):
        problems.append(f"{rel}: 이번 실행에서 아무 시험도 만들지 않았다(고아 — 생성 시험이 없거나 건너뛰었다)")
    for rel in sorted(json_files(repo, PROBE_DIR) - produced):
        problems.append(f"{rel}: 이번 실행에서 아무 시험도 만들지 않았다(실험 표 고아)")
    goldens = sorted((r for r in receipts if r["root"] == "contract"), key=lambda r: r["golden"])
    probes = sorted((r for r in receipts if r["root"] == "probe"), key=lambda r: r["golden"])
    total = sum(os.path.getsize(os.path.join(repo, r["path"])) for r in goldens if os.path.isfile(os.path.join(repo, r["path"])))
    if total > TOTAL_BUDGET:
        problems.append(f"계약 골든 합계 {total} 바이트 — 예산 {TOTAL_BUDGET} 를 넘는다(C§5.3)")
    manifest = {
        "schema": 1,
        "generatedBy": "scripts/golden-export.sh 가 영수증으로 조립한다 — 손으로 고치지 않는다",
        "exportTests": export_tests,
        "goldens": [
            {k: r[k] for k in ("golden", "path", "generator", "swiftSources", "platformSensitive", "equivalence", "cases")}
            for r in goldens
        ],
        "probes": [{k: r[k] for k in ("golden", "path", "generator", "platformSensitive")} for r in probes],
    }
    text = canonical(manifest)
    manifest_path = os.path.join(repo, MANIFEST)
    if mode == "write":
        if not problems:
            with open(manifest_path, "w", encoding="utf-8") as f:
                f.write(text)
    else:
        try:
            with open(manifest_path, encoding="utf-8") as f:
                current = f.read()
        except FileNotFoundError:
            current = None
        if current != text:
            problems.append(f"{MANIFEST} 가 이번 실행의 영수증으로 조립한 목록과 다르다 — CHECK_GOLDEN_WRITE=1 로 다시 쓴다")
    gens = sorted({r["generator"] for r in receipts})
    print(f"golden-digest assemble({mode}): 영수증 {len(receipts)} · 계약 {len(goldens)} · 실험 표 {len(probes)} · "
          f"계약 합계 {total} 바이트 · 생성 시험 파일 {len(gens)}")
    if problems:
        print(f"golden-digest assemble: 문제 {len(problems)}건", file=sys.stderr)
        for p in problems:
            print(f"  - {p}", file=sys.stderr)
        return 1
    return 0


def self_test() -> int:
    """사본 저장소에 결함을 심어 --check 가 빨개지는지 본다(기준선은 같은 사본의 깨끗한 상태 — 초록이어야 한다)."""
    failures: list[str] = []
    # 1) 주석 걷기: 주석·빈 줄만 바꾸면 같은 지문, 코드를 바꾸면 다른 지문, 글자 리터럴 속 // 는 코드다.
    a = 'let x = 1 // 설명\n/* 블록 /* 겹침 */ 끝 */\nlet s = "http://a" // 끝\n'
    b = 'let x = 1 // 다른 설명\n\n\nlet s = "http://a"\n'
    c = 'let x = 2\nlet s = "http://a"\n'
    if swift_source.stripped_sha256(a) != swift_source.stripped_sha256(b):
        failures.append("주석만 바꿨는데 지문이 바뀌었다")
    if swift_source.stripped_sha256(a) == swift_source.stripped_sha256(c):
        failures.append("코드를 바꿨는데 지문이 같다")
    if "http://a" not in swift_source.strip_comments(a):
        failures.append("글자 리터럴 속 // 를 주석으로 걷었다")
    raw = 'let r = #"a // b "# + "\\(f("x // y"))" // 꼬리\n'
    if swift_source.strip_comments(raw).strip() != 'let r = #"a // b "# + "\\(f("x // y"))"':
        failures.append(f"날 글자·보간 처리 오류: {swift_source.strip_comments(raw)!r}")
    # 2) 정규 JSON: 파이썬 출력이 정규 규칙(키 정렬·2칸·끝 줄바꿈·비ASCII 그대로)을 따른다.
    sample = canonical({"b": [1, {}], "a": "한\u0001\""})
    expected = '{\n  "a": "한\\u0001\\"",\n  "b": [\n    1,\n    {}\n  ]\n}\n'
    if sample != expected:
        failures.append(f"정규 JSON 모양이 다르다: {sample!r}")
    # 3) 표준 출력 글자판: Windows 러너의 파이프 stdout 은 ANSI 코드 페이지(cp1252 등)다. 대조(다른 입력): 바꾸기 전엔
    #    한글을 쓰다 죽고, utf8_stdio 를 거친 뒤엔 UTF-8 바이트로 나간다.
    raw_cp1252 = io.TextIOWrapper(io.BytesIO(), encoding="cp1252")
    try:
        raw_cp1252.write("일치")
        raw_cp1252.flush()
        failures.append("대조가 무력하다 — cp1252 스트림이 한글을 받았다")
    except UnicodeEncodeError:
        pass
    fixed_buf = io.BytesIO()
    fixed = io.TextIOWrapper(fixed_buf, encoding="cp1252")
    utf8_stdio((fixed,))
    try:
        fixed.write("일치 — 골든")
        fixed.flush()
        if fixed_buf.getvalue() != "일치 — 골든".encode("utf-8"):
            failures.append(f"utf8_stdio 뒤 바이트가 UTF-8 이 아니다: {fixed_buf.getvalue()!r}")
    except UnicodeEncodeError:
        failures.append("utf8_stdio 를 거쳤는데도 cp1252 스트림에서 한글을 쓰다 죽었다")
    # 4) 저장소 사본에서 --check: 깨끗하면 0, 원본 Swift 코드 한 줄을 바꾸면 1, 주석만 바꾸면 0, 골든 바이트를 바꾸면 1,
    #    바탕(_base) 공용 도구 코드를 바꾸면 1, Windows 식 CRLF 체크아웃은 0(그 위에서 값을 바꾸면 1), 생성 시험 이름 판정.
    checks = 0
    if os.path.isfile(os.path.join(REPO, MANIFEST)) and os.path.isfile(os.path.join(REPO, DIGESTS)):
        manifest = load_manifest(REPO)
        tmp = tempfile.mkdtemp(prefix="golden-digest-selftest-")
        try:
            rels = {MANIFEST, DIGESTS} | set(support_files(REPO))
            for e in manifest["goldens"]:
                rels |= {e["path"], e["generator"], *e["swiftSources"]}
            rels |= {e["generator"] for e in manifest.get("probes", [])}
            for rel in rels:
                dst = os.path.join(tmp, rel)
                os.makedirs(os.path.dirname(dst), exist_ok=True)
                shutil.copyfile(os.path.join(REPO, rel), dst)
            originals = {rel: open(os.path.join(tmp, rel), "rb").read() for rel in rels}

            def restore() -> None:
                for rel, data in originals.items():
                    with open(os.path.join(tmp, rel), "wb") as f:
                        f.write(data)

            def quiet_check() -> int:
                nonlocal checks
                checks += 1
                with open(os.devnull, "w", encoding="utf-8") as null:
                    old_out, old_err = sys.stdout, sys.stderr
                    sys.stdout, sys.stderr = null, null
                    try:
                        return cmd_check(tmp)
                    finally:
                        sys.stdout, sys.stderr = old_out, old_err

            def write_text(rel: str, text: str) -> None:
                with open(os.path.join(tmp, rel), "w", encoding="utf-8", newline="") as f:
                    f.write(text)

            if quiet_check() != 0:
                failures.append("깨끗한 사본에서 --check 가 빨갛다")
            src_rel = manifest["goldens"][0]["swiftSources"][0]
            original = originals[src_rel].decode("utf-8")
            write_text(src_rel, original + "\n// 주석만 더했다\n")
            if quiet_check() != 0:
                failures.append("주석만 더했는데 --check 가 빨갛다")
            write_text(src_rel, original + "\nlet aingcheckPlantedDefect = 1\n")
            if quiet_check() != 1:
                failures.append("원본 Swift 코드를 바꿨는데 --check 가 초록이다")
            restore()
            # 심는 결함은 값 한 글자다. "0x"(hex64) 가 있는 골든을 먼저 고르고, 없으면 첫 골든의 첫 case id 를 바꾼다 —
            # 목록 첫 골든에 "0x" 가 없으면(W1-c 갈래 단독: dates/ailimit.json) replace 가 아무것도 안 바꿔 시험이 헛돌았다.
            def plant(raw: bytes) -> bytes:
                return raw.replace(b'"0x', b'"0X', 1) if b'"0x' in raw else raw.replace(b'"id": "', b'"id": "planted-', 1)
            golden_rel = next((g["path"] for g in manifest["goldens"] if b'"0x' in originals[g["path"]]), manifest["goldens"][0]["path"])
            data = originals[golden_rel]
            if plant(data) == data:
                failures.append(f"심은 결함이 골든 바이트를 못 바꿨다({golden_rel}) — 자기 시험이 헛돈다")
            with open(os.path.join(tmp, golden_rel), "wb") as f:
                f.write(plant(data))
            if quiet_check() != 1:
                failures.append("골든 바이트를 바꿨는데 --check 가 초록이다")
            restore()
            base_rels = [r for r in support_files(tmp) if "/GoldenExport/_base/" in r and r != manifest["goldens"][0]["generator"]]
            if not base_rels:
                failures.append("지문 support 에 GoldenExport/_base 공용 파일이 하나도 없다")
            else:
                write_text(base_rels[0], originals[base_rels[0]].decode("utf-8") + "\nlet aingcheckPlantedBaseDefect = 1\n")
                if quiet_check() != 1:
                    failures.append(f"바탕 공용 파일 {base_rels[0]} 코드를 바꿨는데 --check 가 초록이다")
                restore()
            # Windows 체크아웃(core.autocrlf=true): 글자 파일 전부가 CRLF 로 풀린다.
            for rel, raw in originals.items():
                with open(os.path.join(tmp, rel), "wb") as f:
                    f.write(raw.replace(b"\r\n", b"\n").replace(b"\n", b"\r\n"))
            if quiet_check() != 0:
                failures.append("CRLF 로 풀린 체크아웃(Windows autocrlf)에서 --check 가 빨갛다")
            crlf_golden = open(os.path.join(tmp, golden_rel), "rb").read()
            with open(os.path.join(tmp, golden_rel), "wb") as f:
                f.write(plant(crlf_golden))
            if quiet_check() != 1:
                failures.append("CRLF 체크아웃 위에서 골든 값을 바꿨는데 --check 가 초록이다(줄 끝 접기가 값까지 가렸다)")
            restore()
            orphan = os.path.join(tmp, CONTRACT_DIR, "rng", "planted-orphan.json")
            with open(orphan, "w", encoding="utf-8") as f:
                f.write("{}\n")
            if quiet_check() != 1:
                failures.append("목록에 없는 골든 파일(고아)을 심었는데 --check 가 초록이다")
            os.remove(orphan)
            # 생성 시험 이름 판정(Swift 정적 잠금에서 옮겨 왔다 — 주석 걷기는 swift_source 한 벌).
            if generator_problems(tmp, manifest):
                failures.append(f"깨끗한 사본에서 생성 시험 이름 판정이 빨갛다: {generator_problems(tmp, manifest)}")
            name = manifest["goldens"][0]["golden"]
            gen_rel = manifest["goldens"][0]["generator"]
            gen_text = originals[gen_rel].decode("utf-8")
            needle = f'golden: "{name}"'
            if needle not in gen_text:
                failures.append(f"생성 시험 {gen_rel} 에 {needle} 이 없어 이름 판정 대조를 못 했다")
            else:
                planted = {
                    "줄 주석에만": f'golden: aingcheckName // {needle}',
                    "블록 주석에만": f'golden: aingcheckName /* {needle} */',
                    "역빗금 글자 뒤 줄 주석에만": f'golden: "\\\\" // {needle}',
                }
                for label, replacement in planted.items():
                    write_text(gen_rel, gen_text.replace(needle, replacement))
                    hits = [p for p in generator_problems(tmp, manifest) if name in p and "글자 리터럴" in p]
                    if not hits:
                        failures.append(f"이름이 {label} 남았는데 생성 시험 이름 판정이 초록이다")
                    if quiet_check() != 1:
                        failures.append(f"이름이 {label} 남았는데 --check 가 초록이다")
                restore()
                os.remove(os.path.join(tmp, gen_rel))
                if not any("가 없다" in p and gen_rel in p for p in generator_problems(tmp, manifest)):
                    failures.append("생성 시험 파일을 지웠는데 이름 판정이 초록이다")
                restore()
                outside = json.loads(json.dumps(manifest))
                outside["goldens"][0]["generator"] = "Tests/checkTests/NotGolden.swift"
                if not any("밖이다" in p for p in generator_problems(tmp, outside)):
                    failures.append("생성 시험이 GoldenExport 폴더 밖인데 이름 판정이 초록이다")
        finally:
            shutil.rmtree(tmp, ignore_errors=True)
    else:
        failures.append(f"{MANIFEST}·{DIGESTS} 가 없어 저장소 사본 시험을 못 했다")
    if failures:
        print("golden-digest --self-test: 실패", file=sys.stderr)
        for f_ in failures:
            print(f"  - {f_}", file=sys.stderr)
        return 1
    print(f"golden-digest --self-test: 통과(주석 걷기 4 · 정규 JSON 1 · 글자판 2 · 사본 --check {checks} · 생성 시험 이름 판정 6)")
    return 0


def utf8_stdio(streams=None) -> None:
    """표준 출력·오류를 UTF-8 로 바꾼다. Windows 러너에서 파이프로 이어진 stdout 은 ANSI 코드 페이지(cp1252 등)라
    한글을 찍다 UnicodeEncodeError 로 죽는다. `python3 -I` 는 PYTHONIOENCODING·PYTHONUTF8 을 무시하므로 여기서 바꾼다."""
    for stream in streams if streams is not None else (sys.stdout, sys.stderr):
        reconfigure = getattr(stream, "reconfigure", None)
        if reconfigure is not None:
            reconfigure(encoding="utf-8", errors="backslashreplace")


def main(argv: list[str]) -> int:
    utf8_stdio()
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("command", nargs="?", choices=["assemble"])
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--write", action="store_true")
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--run")
    parser.add_argument("--mode", choices=["compare", "write"])
    parser.add_argument("--export-tests", type=int, default=-1,
                        help="전체 스위트 목록의 GoldenExport 시험 수(golden-export.sh 가 넘긴다 — _manifest.json 에 박는다)")
    parser.add_argument("--repo", default=REPO)
    args = parser.parse_args(argv)
    if args.command == "assemble":
        if not args.run or not args.mode:
            parser.error("assemble 은 --run DIR --mode compare|write 가 필요하다")
        if args.export_tests < 1:
            parser.error("assemble 은 --export-tests N(1 이상)이 필요하다")
        return cmd_assemble(args.repo, args.run, args.mode, args.export_tests)
    if args.self_test:
        return self_test()
    if args.write:
        return cmd_write(args.repo)
    if args.check:
        return cmd_check(args.repo)
    parser.error("--check · --write · assemble · --self-test 중 하나")
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
