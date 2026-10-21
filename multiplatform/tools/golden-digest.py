#!/usr/bin/env python3
"""골든 신선도 셋째 겹(C§5.4 ③, W0-b) — Swift 없는 CI 가 "맥에서 골든을 다시 돌려야 하는가"를 안다.

  python3 -I multiplatform/tools/golden-digest.py --check      _digests.json 을 다시 셈해 비교(CI 의 golden-digest 잡 · gate-fast)
  python3 -I multiplatform/tools/golden-digest.py --write      _digests.json 을 다시 쓴다(scripts/golden-export.sh 쓰기 모드가 부른다)
  python3 -I multiplatform/tools/golden-digest.py assemble --run DIR --mode compare|write --export-tests N
                                                               영수증(DIR/receipts) → _manifest.json 조립 · 고아 검사
  python3 -I multiplatform/tools/golden-digest.py --self-test  결함을 심은 사본으로 빨강을 확인

지문(_digests.json): 계약 골든(_manifest.json 의 goldens)마다
  · file          골든 파일 바이트의 sha256(손으로 고친 골든을 잡는다)
  · generator     생성 시험 Swift 파일의 주석 걷은 sha256
  · swiftSources  원본 Swift 파일마다 주석 걷은 sha256(엔진만 고친 main 커밋도 잡는다 — §8-10)
  · support       Tests/CheckGoldenSupport/*.swift(작성기) 의 주석 걷은 sha256 — 모든 골든에 공통
주석 걷기는 swift_source.py 한 벌(C§5.4 "Python 한 벌"). 주석·빈 줄만 바꾼 커밋은 지문이 그대로다.
실험 표(probes)는 지문에 넣지 않는다 — 계약이 아니고, 맥 비교 모드가 지킨다.

정규 JSON = json.dumps(값, indent=2, sort_keys=True, ensure_ascii=False) + "\\n" (Swift GoldenJSON.canonicalText 와 바이트가 같다).
종료 코드: 0 일치 · 1 불일치/문제 · 2 사용법·파일 없음.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
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


def compute_digests(repo: str, manifest: dict) -> dict:
    support_dir = os.path.join(repo, SUPPORT_DIR)
    support = {}
    if os.path.isdir(support_dir):
        for name in sorted(os.listdir(support_dir)):
            if name.endswith(".swift"):
                rel = f"{SUPPORT_DIR}/{name}"
                support[rel] = swift_source.stripped_sha256(read_text(repo, rel))
    goldens = {}
    for entry in manifest.get("goldens", []):
        name = entry["golden"]
        goldens[name] = {
            "file": hashlib.sha256(read_bytes(repo, entry["path"])).hexdigest(),
            "generator": {entry["generator"]: swift_source.stripped_sha256(read_text(repo, entry["generator"]))},
            "swiftSources": {src: swift_source.stripped_sha256(read_text(repo, src)) for src in entry["swiftSources"]},
        }
    return {
        "schema": 1,
        "strip": "swift_source.strip_comments v1 — 주석·빈 줄·줄 끝 공백을 뺀 UTF-8 의 sha256",
        "support": support,
        "goldens": goldens,
    }


def diff_digests(want: dict, have: dict) -> list[str]:
    problems: list[str] = []
    for key in ("schema", "strip"):
        if want.get(key) != have.get(key):
            problems.append(f"{key}: 기록 {have.get(key)!r} ≠ 지금 {want.get(key)!r}")
    for rel in sorted(set(want.get("support", {})) | set(have.get("support", {}))):
        w, h = want.get("support", {}).get(rel), have.get("support", {}).get(rel)
        if w != h:
            problems.append(f"작성기 {rel}: 기록 {str(h)[:12]} ≠ 지금 {str(w)[:12]}")
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
    if problems:
        print(f"golden-digest --check: 불일치 {len(problems)}건 — {RERUN}", file=sys.stderr)
        for p in problems:
            print(f"  - {p}", file=sys.stderr)
        return 1
    print(f"golden-digest --check: 일치 — 골든 {len(want['goldens'])} · 작성기 파일 {len(want['support'])}")
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
    # 3) 저장소 사본에서 --check: 깨끗하면 0, 원본 Swift 코드 한 줄을 바꾸면 1, 주석만 바꾸면 0, 골든 바이트를 바꾸면 1.
    if os.path.isfile(os.path.join(REPO, MANIFEST)) and os.path.isfile(os.path.join(REPO, DIGESTS)):
        manifest = load_manifest(REPO)
        tmp = tempfile.mkdtemp(prefix="golden-digest-selftest-")
        try:
            rels = {MANIFEST, DIGESTS} | {f"{SUPPORT_DIR}/{n}" for n in os.listdir(os.path.join(REPO, SUPPORT_DIR)) if n.endswith(".swift")}
            for e in manifest["goldens"]:
                rels |= {e["path"], e["generator"], *e["swiftSources"]}
            for rel in rels:
                dst = os.path.join(tmp, rel)
                os.makedirs(os.path.dirname(dst), exist_ok=True)
                shutil.copyfile(os.path.join(REPO, rel), dst)

            def quiet_check() -> int:
                with open(os.devnull, "w") as null:
                    old_out, old_err = sys.stdout, sys.stderr
                    sys.stdout, sys.stderr = null, null
                    try:
                        return cmd_check(tmp)
                    finally:
                        sys.stdout, sys.stderr = old_out, old_err

            if quiet_check() != 0:
                failures.append("깨끗한 사본에서 --check 가 빨갛다")
            src = os.path.join(tmp, manifest["goldens"][0]["swiftSources"][0])
            original = open(src, encoding="utf-8").read()
            with open(src, "w", encoding="utf-8") as f:
                f.write(original + "\n// 주석만 더했다\n")
            if quiet_check() != 0:
                failures.append("주석만 더했는데 --check 가 빨갛다")
            with open(src, "w", encoding="utf-8") as f:
                f.write(original + "\nlet aingcheckPlantedDefect = 1\n")
            if quiet_check() != 1:
                failures.append("원본 Swift 코드를 바꿨는데 --check 가 초록이다")
            with open(src, "w", encoding="utf-8") as f:
                f.write(original)
            golden = os.path.join(tmp, manifest["goldens"][0]["path"])
            data = open(golden, "rb").read()
            with open(golden, "wb") as f:
                f.write(data.replace(b'"0x', b'"0X', 1))
            if quiet_check() != 1:
                failures.append("골든 바이트를 바꿨는데 --check 가 초록이다")
            with open(golden, "wb") as f:
                f.write(data)
            orphan = os.path.join(tmp, CONTRACT_DIR, "rng", "planted-orphan.json")
            with open(orphan, "w", encoding="utf-8") as f:
                f.write("{}\n")
            if quiet_check() != 1:
                failures.append("목록에 없는 골든 파일(고아)을 심었는데 --check 가 초록이다")
        finally:
            shutil.rmtree(tmp, ignore_errors=True)
    else:
        failures.append(f"{MANIFEST}·{DIGESTS} 가 없어 저장소 사본 시험을 못 했다")
    if failures:
        print("golden-digest --self-test: 실패", file=sys.stderr)
        for f_ in failures:
            print(f"  - {f_}", file=sys.stderr)
        return 1
    print("golden-digest --self-test: 통과(주석 걷기 4 · 정규 JSON 1 · 사본 --check 5)")
    return 0


def main(argv: list[str]) -> int:
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
