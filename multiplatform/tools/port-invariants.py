#!/usr/bin/env python3
"""주석으로만 남은 사고 방지 규약(INV) 스캐너(C§4.2, W0-b). 실행은 `python3 -I multiplatform/tools/port-invariants.py …`.

Swift 소스의 ★·⚠️ 표식 하나가 규약 하나다. 표식이 든 주석 줄에서 시작해, 같은 주석 묶음(이어지는 `//`·`///` 줄)에서
다음 표식 줄·빈 주석 줄·묶음 끝 앞까지를 그 규약의 본문으로 본다. 코드 꼬리 주석(`x = 1 // ⚠️ …`)은 그 줄 하나다.
글자 리터럴 안의 ★·⚠️ 는 규약이 아니다(swift_source.py 가 가른다).

ID = INV-<파일 이름(확장자 뺌)>-<정규화 본문 sha256 앞 8자>. 줄 번호는 흔들리므로 ID 에 넣지 않는다.
같은 파일에 같은 본문이 또 있으면 뒤의 것에 -2, -3 … 을 붙인다. 파일 이름이 영역 사이에서 겹치면 영역 접두(core. mac. phone.)를 붙인다.

훑는 범위(C§0 #6 의 셈: 코어 · 맥 스토어 · 폰):
  core   Sources/CheckCore/**
  mac    Sources/check/WorkTimerStore*.swift
  phone  Sources/CheckMobileKit/** · Sources/CheckMobileShared/**

Kotlin 쪽 표기(셋 중 하나 — 시험 이름·주석 아무 데나):
  @Inv("INV-…")              시험이나 구현에 붙인 주석/애너테이션
  // INV-… 이식: 이유          구현 주석
  multiplatform/tools/inv-na.txt 의 "INV-… 해당 없음: 이유" 줄

  python3 -I multiplatform/tools/port-invariants.py                 영역별 개수와 합계
  python3 -I multiplatform/tools/port-invariants.py --list          ID · 영역 · 파일:줄 · 첫 줄(TSV)
  python3 -I multiplatform/tools/port-invariants.py --json OUT      전체 목록 JSON
  python3 -I multiplatform/tools/port-invariants.py --coverage --files Sources/CheckCore/TetrisGame.swift[:10-200] …
        → 그 파일(줄 구간)의 ID 가 Kotlin·inv-na.txt 에 표기된 비율. 100% 가 아니면 종료 1 과 빠진 ID 목록
  python3 -I multiplatform/tools/port-invariants.py --self-test     결함을 심은 가짜 소스로 판정을 확인
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.dont_write_bytecode = True
import swift_source  # noqa: E402

REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
AREAS = [
    ("core", "Sources/CheckCore", None),
    ("mac", "Sources/check", re.compile(r"^WorkTimerStore.*\.swift$")),
    ("phone", "Sources/CheckMobileKit", None),
    ("phone", "Sources/CheckMobileShared", None),
]
INV_NA = "multiplatform/tools/inv-na.txt"
KOTLIN_ROOT = "multiplatform"
ID_RE = re.compile(r"INV-[A-Za-z0-9_.]+-[0-9a-f]{8}(?:-\d+)?")


def swift_files(repo: str) -> list[tuple[str, str]]:
    out: list[tuple[str, str]] = []
    for area, rel, pattern in AREAS:
        base = os.path.join(repo, rel)
        for dirpath, _dirs, files in os.walk(base):
            for name in files:
                if not name.endswith(".swift"):
                    continue
                if pattern is not None and (dirpath != base or not pattern.match(name)):
                    continue
                out.append((area, os.path.relpath(os.path.join(dirpath, name), repo).replace(os.sep, "/")))
    return sorted(out, key=lambda t: t[1])


def invariants_in(text: str) -> list[tuple[int, str, str]]:
    """(첫 줄 번호, 정규화 본문, 첫 줄 원문) 목록."""
    lines = swift_source.comment_lines(text)
    out: list[tuple[int, str, str]] = []
    current: list | None = None   # [첫 줄, [본문 조각], 첫 줄 원문, 마지막 줄]

    def close() -> None:
        nonlocal current
        if current is not None:
            out.append((current[0], " ".join(p for p in current[1] if p), current[2]))
        current = None

    for line_no, comment, whole in lines:
        body = swift_source.normalize_comment(comment)
        marked = swift_source.has_marker(comment)
        contiguous = current is not None and whole and line_no == current[3] + 1
        if marked:
            close()
            current = [line_no, [body], comment.strip(), line_no]
            if not whole:
                close()   # 코드 꼬리 주석은 그 줄 하나
            continue
        if contiguous and body:
            current[1].append(body)
            current[3] = line_no
        else:
            close()
    close()
    return out


def scan(repo: str) -> list[dict]:
    files = swift_files(repo)
    stems: dict[str, set[str]] = {}
    for area, rel in files:
        stems.setdefault(os.path.splitext(os.path.basename(rel))[0], set()).add(area)
    items: list[dict] = []
    for area, rel in files:
        with open(os.path.join(repo, rel), encoding="utf-8") as f:
            text = f.read()
        stem = os.path.splitext(os.path.basename(rel))[0]
        abbr = stem if len(stems[stem]) == 1 else f"{area}.{stem}"
        seen: dict[str, int] = {}
        for line_no, body, first in invariants_in(text):
            digest = hashlib.sha256(body.encode("utf-8")).hexdigest()[:8]
            base = f"INV-{abbr}-{digest}"
            seen[base] = seen.get(base, 0) + 1
            inv_id = base if seen[base] == 1 else f"{base}-{seen[base]}"
            items.append({"id": inv_id, "area": area, "file": rel, "line": line_no, "first": first[:160]})
    return items


def kotlin_marks(repo: str) -> set[str]:
    marks: set[str] = set()
    root = os.path.join(repo, KOTLIN_ROOT)
    for dirpath, dirs, files in os.walk(root):
        dirs[:] = [d for d in dirs if d not in ("build", ".gradle", ".kotlin", ".idea")]
        for name in files:
            if name.endswith((".kt", ".kts")):
                with open(os.path.join(dirpath, name), encoding="utf-8") as f:
                    text = f.read()
                for m in re.finditer(r'@Inv\(\s*"(' + ID_RE.pattern + r')"\s*\)', text):
                    marks.add(m.group(1))
                for m in re.finditer(r"(" + ID_RE.pattern + r")\s+이식\s*:", text):
                    marks.add(m.group(1))
    na = os.path.join(repo, INV_NA)
    if os.path.isfile(na):
        with open(na, encoding="utf-8") as f:
            for line in f:
                m = re.match(r"\s*(" + ID_RE.pattern + r")\s+해당 없음\s*:\s*\S", line)
                if m:
                    marks.add(m.group(1))
    return marks


def parse_file_spec(spec: str) -> tuple[str, int, int]:
    if ":" in spec:
        path, span = spec.rsplit(":", 1)
        lo, hi = span.split("-")
        return path, int(lo), int(hi)
    return spec, 1, 10**9


def coverage(items: list[dict], specs: list[str], marks: set[str]) -> tuple[list[dict], list[dict]]:
    wanted = [parse_file_spec(s) for s in specs]
    owned = [it for it in items if any(it["file"] == p and lo <= it["line"] <= hi for p, lo, hi in wanted)]
    missing = [it for it in owned if it["id"] not in marks]
    return owned, missing


def self_test() -> int:
    failures: list[str] = []
    src = (
        '/// ★ 첫 규약: 순서를 지킨다.\n'
        '///   이어지는 설명 줄.\n'
        '/// 보통 설명.\n'
        '///\n'
        '/// ⚠️ 둘째 규약.\n'
        'let s = "★ 글자 속 표식은 규약이 아니다"\n'
        'let x = 1 // ⚠️ 꼬리 규약\n'
        '// ⚠️ 둘째 규약.\n'
        '/* 블록 ★ 규약\n   이어짐 */\n'
    )
    got = invariants_in(src)
    bodies = [b for _, b, _ in got]
    if len(got) != 5:
        failures.append(f"규약 5개를 기대했는데 {len(got)}: {bodies}")
    if any("글자 속" in b for b in bodies):
        failures.append("글자 리터럴 속 ★ 를 규약으로 셌다")
    if not any(b.startswith("★ 첫 규약") and "이어지는 설명 줄" in b and "보통 설명" in b for b in bodies):
        failures.append(f"이어지는 주석 줄을 본문에 넣지 않았다: {bodies}")
    if not any(b == "⚠️ 꼬리 규약" for b in bodies):
        failures.append("코드 꼬리 주석 규약을 못 셌다")
    with tempfile.TemporaryDirectory() as tmp:
        os.makedirs(os.path.join(tmp, "Sources/CheckCore"))
        os.makedirs(os.path.join(tmp, "Sources/check"))
        os.makedirs(os.path.join(tmp, "Sources/CheckMobileKit/Now"))
        os.makedirs(os.path.join(tmp, "multiplatform/tools"))
        with open(os.path.join(tmp, "Sources/CheckCore/Rule.swift"), "w", encoding="utf-8") as f:
            f.write(src)
        with open(os.path.join(tmp, "Sources/check/WorkTimerStore.swift"), "w", encoding="utf-8") as f:
            f.write("// ★ 맥 규약\n")
        with open(os.path.join(tmp, "Sources/check/CheckMenuView.swift"), "w", encoding="utf-8") as f:
            f.write("// ★ 화면 — 범위 밖\n")
        with open(os.path.join(tmp, "Sources/CheckMobileKit/Now/Rule.swift"), "w", encoding="utf-8") as f:
            f.write("// ★ 폰 규약\n")
        items = scan(tmp)
        areas = sorted({(it["area"], it["file"]) for it in items})
        if ("mac", "Sources/check/CheckMenuView.swift") in areas:
            failures.append("맥 스토어 밖 파일을 셌다")
        ids = [it["id"] for it in items]
        if len(ids) != len(set(ids)):
            failures.append(f"ID 가 겹친다: {ids}")
        if not any(i.startswith("INV-core.Rule-") for i in ids) or not any(i.startswith("INV-phone.Rule-") for i in ids):
            failures.append(f"영역 사이 같은 파일 이름에 접두를 안 붙였다: {ids}")
        dup = [i for i in ids if re.search(r"-\d+$", i) and not re.search(r"-[0-9a-f]{8}$", i)]
        if len(dup) != 1:
            failures.append(f"같은 본문 둘째 것에 -2 를 붙이지 않았다: {ids}")
        # 이동해도 ID 가 같다(줄 번호 무관).
        with open(os.path.join(tmp, "Sources/CheckCore/Rule.swift"), "w", encoding="utf-8") as f:
            f.write("\n\n\n" + src)
        moved = [it["id"] for it in scan(tmp)]
        if sorted(moved) != sorted(ids):
            failures.append("줄만 옮겼는데 ID 가 바뀌었다")
        # 표기율: 하나만 표기하면 나머지가 빠진 목록에 남는다.
        first_core = next(i for i in ids if i.startswith("INV-core.Rule-"))
        with open(os.path.join(tmp, "multiplatform/tools/inv-na.txt"), "w", encoding="utf-8") as f:
            f.write(f"{first_core} 해당 없음: 시험\n")
        owned, missing = coverage(scan(tmp), ["Sources/CheckCore/Rule.swift"], kotlin_marks(tmp))
        if len(owned) != 5 or len(missing) != 4:
            failures.append(f"표기율: 소유 {len(owned)} · 빠짐 {len(missing)}(기대 5 · 4)")
    if failures:
        print("port-invariants --self-test: 실패", file=sys.stderr)
        for f_ in failures:
            print(f"  - {f_}", file=sys.stderr)
        return 1
    print("port-invariants --self-test: 통과(묶음 · 글자 리터럴 · 꼬리 주석 · 범위 · 접두 · 겹친 본문 · 줄 이동 · 표기율)")
    return 0


def main(argv: list[str]) -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--repo", default=REPO)
    p.add_argument("--list", action="store_true")
    p.add_argument("--json")
    p.add_argument("--coverage", action="store_true")
    p.add_argument("--files", nargs="*", default=[])
    p.add_argument("--self-test", action="store_true")
    args = p.parse_args(argv)
    if args.self_test:
        return self_test()
    items = scan(args.repo)
    if args.coverage:
        if not args.files:
            p.error("--coverage 는 --files 경로[:시작-끝] … 가 필요하다")
        owned, missing = coverage(items, args.files, kotlin_marks(args.repo))
        rate = 100.0 if not owned else 100.0 * (len(owned) - len(missing)) / len(owned)
        print(f"port-invariants coverage: 소유 {len(owned)} · 표기 {len(owned) - len(missing)} · 표기율 {rate:.1f}%")
        for it in missing:
            print(f"  빠짐 {it['id']}\t{it['file']}:{it['line']}\t{it['first']}")
        return 0 if not missing else 1
    if args.json:
        with open(args.json, "w", encoding="utf-8") as f:
            json.dump(items, f, ensure_ascii=False, indent=2, sort_keys=True)
            f.write("\n")
    if args.list:
        for it in items:
            print(f"{it['id']}\t{it['area']}\t{it['file']}:{it['line']}\t{it['first']}")
    counts: dict[str, int] = {}
    for it in items:
        counts[it["area"]] = counts.get(it["area"], 0) + 1
    print(f"port-invariants: 합계 {len(items)} · " + " · ".join(f"{a} {counts.get(a, 0)}" for a in ("core", "mac", "phone")))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
