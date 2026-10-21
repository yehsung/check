#!/usr/bin/env python3
"""갈래 소유 검사(§8-3, W0-a). 실행은 `python3 -I multiplatform/tools/lane-ownership.py …`.

브랜치 diff(기준...머리)의 경로마다 판정한다:
  1. 옛 경로(§8-1: 꼭대기 xplat/ kmp/ contracts/ tools/ backups/ supabase/)  → 빨강
  2. 예약 경로인데 이 갈래가 예약 목록에 없음                                   → 빨강
  3. 이 갈래 owns 글롭 밖이거나 excludes 에 걸림                                 → 빨강
빨강이 하나라도 있으면 종료 코드 1. 마지막 줄에 "소유 밖 변경 N" 을 찍는다(완료 보고에 붙인다).

  --lane W0-a [--base xplat/main] [--head HEAD]   git diff --no-renames --name-only base...head
  --lane W0-a --names-from FILE                    경로 목록 파일(한 줄에 하나, '#' 주석) — 가짜 diff 로 시험할 때
  --include-worktree                               커밋 안 된 변경(git status)도 더한다
  --validate                                       lanes.yml 문법·글롭·패키지 표만 확인
  --self-test                                      위반을 심은 가짜 diff 로 빨강을 확인(자기 시험)

lanes.yml 은 YAML 부분집합이다(이 파일의 parse_yaml 이 읽는다). 바깥 패키지(PyYAML)에 기대지 않는다(-I 실행).
"""
from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_LANES = os.path.join(HERE, "lanes.yml")


# ---------------- YAML 부분집합 ----------------

class YamlError(Exception):
    pass


def _strip_comment(line: str) -> str:
    out, quote = [], None
    for i, ch in enumerate(line):
        if quote:
            out.append(ch)
            if ch == quote:
                quote = None
            continue
        if ch in "\"'":
            quote = ch
            out.append(ch)
            continue
        if ch == "#" and (i == 0 or line[i - 1] in " \t"):
            break
        out.append(ch)
    return "".join(out).rstrip()


def _scalar(text: str, lineno: int):
    text = text.strip()
    if text == "":
        return None
    if text[0] in "\"'":
        if len(text) < 2 or text[-1] != text[0]:
            raise YamlError(f"{lineno}: 닫히지 않은 따옴표: {text}")
        return text[1:-1]
    if text.startswith("["):
        if not text.endswith("]"):
            raise YamlError(f"{lineno}: 닫히지 않은 흐름 목록: {text}")
        inner = text[1:-1].strip()
        if not inner:
            return []
        return [_scalar(part, lineno) for part in _split_flow(inner, lineno)]
    if text.startswith("{"):
        raise YamlError(f"{lineno}: 흐름 매핑은 지원하지 않는다: {text}")
    if text.isdigit():
        return int(text)
    return text


def _split_flow(inner: str, lineno: int):
    parts, cur, quote = [], [], None
    for ch in inner:
        if quote:
            cur.append(ch)
            if ch == quote:
                quote = None
            continue
        if ch in "\"'":
            quote = ch
            cur.append(ch)
        elif ch == ",":
            parts.append("".join(cur))
            cur = []
        else:
            cur.append(ch)
    if quote:
        raise YamlError(f"{lineno}: 흐름 목록 안 따옴표가 닫히지 않았다")
    parts.append("".join(cur))
    return [p.strip() for p in parts]


def _split_key(content: str, lineno: int):
    """'key: value' → (key, value). 키는 따옴표일 수 있다."""
    if content[0] in "\"'":
        q = content[0]
        end = content.find(q, 1)
        if end < 0:
            raise YamlError(f"{lineno}: 닫히지 않은 키 따옴표")
        key = content[1:end]
        rest = content[end + 1:]
        if not rest.startswith(":"):
            raise YamlError(f"{lineno}: 키 뒤에 ':' 가 없다")
        return key, rest[1:]
    idx = content.find(":")
    if idx < 0:
        raise YamlError(f"{lineno}: 매핑 줄에 ':' 가 없다: {content}")
    if idx + 1 < len(content) and content[idx + 1] not in " \t":
        raise YamlError(f"{lineno}: ':' 뒤에는 공백이 와야 한다: {content}")
    return content[:idx].strip(), content[idx + 1:]


def parse_yaml(text: str):
    lines = []
    for n, raw in enumerate(text.splitlines(), 1):
        if "\t" in raw[: len(raw) - len(raw.lstrip())]:
            raise YamlError(f"{n}: 들여쓰기에 탭을 쓰지 않는다")
        body = _strip_comment(raw)
        if body.strip() == "":
            continue
        indent = len(body) - len(body.lstrip(" "))
        lines.append((n, indent, body.strip()))

    pos = 0

    def parse_block(indent: int):
        nonlocal pos
        if pos >= len(lines):
            return None
        n, ind, content = lines[pos]
        if ind != indent:
            raise YamlError(f"{n}: 들여쓰기가 맞지 않는다(기대 {indent}, 실제 {ind})")
        if content.startswith("- ") or content == "-":
            seq = []
            while pos < len(lines) and lines[pos][1] == indent and (lines[pos][2].startswith("- ") or lines[pos][2] == "-"):
                n, _, content = lines[pos]
                item = content[1:].strip()
                if item == "" or (":" in item and not item.startswith(("\"", "'", "["))):
                    raise YamlError(f"{n}: 목록 항목은 스칼라만 쓴다")
                seq.append(_scalar(item, n))
                pos += 1
            return seq
        mapping = {}
        while pos < len(lines) and lines[pos][1] == indent:
            n, _, content = lines[pos]
            if content.startswith("- "):
                raise YamlError(f"{n}: 매핑 안에 목록 항목이 섞였다")
            key, rest = _split_key(content, n)
            if key in mapping:
                raise YamlError(f"{n}: 키가 겹친다: {key}")
            pos += 1
            if rest.strip() == "":
                if pos < len(lines) and lines[pos][1] > indent:
                    mapping[key] = parse_block(lines[pos][1])
                elif pos < len(lines) and lines[pos][1] == indent and lines[pos][2].startswith("- "):
                    mapping[key] = parse_block(indent)
                else:
                    mapping[key] = None
            else:
                mapping[key] = _scalar(rest, n)
        if pos < len(lines) and lines[pos][1] > indent:
            raise YamlError(f"{lines[pos][0]}: 예상하지 못한 들여쓰기")
        return mapping

    if not lines:
        return {}
    result = parse_block(lines[0][1])
    if pos != len(lines):
        raise YamlError(f"{lines[pos][0]}: 남은 줄을 읽지 못했다")
    return result


# ---------------- 글롭 ----------------

def expand_braces(pattern: str):
    m = re.search(r"\{([^{}]*)\}", pattern)
    if not m:
        return [pattern]
    head, tail = pattern[: m.start()], pattern[m.end():]
    out = []
    for alt in m.group(1).split(","):
        out.extend(expand_braces(head + alt + tail))
    return out


def glob_to_regex(glob: str) -> re.Pattern:
    i, out = 0, []
    while i < len(glob):
        if glob.startswith("**/", i):
            out.append("(?:[^/]+/)*")
            i += 3
        elif glob.startswith("**", i):
            out.append(".*")
            i += 2
        elif glob[i] == "*":
            out.append("[^/]*")
            i += 1
        elif glob[i] == "?":
            out.append("[^/]")
            i += 1
        else:
            out.append(re.escape(glob[i]))
            i += 1
    return re.compile("^" + "".join(out) + "$")


class Lanes:
    def __init__(self, data: dict):
        if not isinstance(data, dict) or data.get("version") != 1:
            raise YamlError("version: 1 이 아니다")
        self.package_root = data.get("package_root") or {}
        self.forbidden = [self._compile(g) for g in (data.get("forbidden") or [])]
        self.forbidden_src = list(data.get("forbidden") or [])
        self.reserved = []
        for glob, allowed in (data.get("reserved") or {}).items():
            if not isinstance(allowed, list) or not allowed:
                raise YamlError(f"reserved '{glob}' 의 갈래 목록이 비었다")
            self.reserved.append((glob, self._compile(glob), set(allowed)))
        coord = data.get("coordinator") or {}
        self.lanes = {"coordinator": {"wave": "*", "owns": coord.get("owns") or [], "excludes": [], "golden": []}}
        for name, spec in (data.get("lanes") or {}).items():
            if not isinstance(spec, dict) or not spec.get("owns"):
                raise YamlError(f"갈래 {name} 의 owns 가 없다")
            self.lanes[name] = spec
        self.owns = {n: [self._compile(g) for g in s.get("owns") or []] for n, s in self.lanes.items()}
        self.excludes = {n: [self._compile(g) for g in s.get("excludes") or []] for n, s in self.lanes.items()}
        for glob, _, allowed in self.reserved:
            unknown = allowed - set(self.lanes)
            if unknown:
                raise YamlError(f"reserved '{glob}' 에 없는 갈래: {sorted(unknown)}")

    def _substitute(self, glob: str) -> str:
        def repl(m):
            module = m.group(1)
            if module not in self.package_root:
                raise YamlError(f"package_root 에 없는 모듈: {module} (글롭 {glob})")
            return self.package_root[module]
        return re.sub(r"\{pkg:([^}]+)\}", repl, glob)

    def _compile(self, glob: str):
        if not isinstance(glob, str) or not glob or glob.startswith("/") or ".." in glob.split("/"):
            raise YamlError(f"잘못된 글롭: {glob!r}")
        return [glob_to_regex(g) for g in expand_braces(self._substitute(glob))]

    @staticmethod
    def _match(compiled, path):
        return any(r.match(path) for r in compiled)

    def judge(self, lane: str, path: str):
        """(판정, 이유). 판정은 ok|forbidden|reserved|outside."""
        if lane not in self.lanes:
            raise KeyError(lane)
        for src, comp in zip(self.forbidden_src, self.forbidden):
            if self._match(comp, path):
                return "forbidden", f"옛 경로(§8-1) {src}"
        for glob, comp, allowed in self.reserved:
            if self._match(comp, path) and lane not in allowed:
                return "reserved", f"예약 경로 {glob} → {sorted(allowed)}"
        if any(self._match(c, path) for c in self.excludes[lane]):
            return "outside", "이 갈래 excludes 에 걸림"
        if any(self._match(c, path) for c in self.owns[lane]):
            return "ok", ""
        return "outside", "이 갈래 owns 밖"


def load_lanes(path: str) -> Lanes:
    with open(path, encoding="utf-8") as f:
        return Lanes(parse_yaml(f.read()))


# ---------------- git ----------------

def repo_root() -> str:
    return subprocess.run(["git", "rev-parse", "--show-toplevel"], check=True, capture_output=True, text=True, cwd=HERE).stdout.strip()


def changed_paths(base: str, head: str, include_worktree: bool):
    root = repo_root()
    out = subprocess.run(["git", "diff", "--no-renames", "--name-only", f"{base}...{head}"],
                         check=True, capture_output=True, text=True, cwd=root).stdout.splitlines()
    paths = set(p for p in out if p)
    if include_worktree:
        st = subprocess.run(["git", "status", "--porcelain", "--untracked-files=all", "--no-renames"],
                            check=True, capture_output=True, text=True, cwd=root).stdout.splitlines()
        for line in st:
            if len(line) > 3:
                paths.add(line[3:].strip().strip('"'))
    return sorted(paths)


def read_names(path: str):
    with open(path, encoding="utf-8") as f:
        return sorted({ln.strip() for ln in f if ln.strip() and not ln.strip().startswith("#")})


def report(lanes: Lanes, lane: str, paths, stream=sys.stdout) -> int:
    bad = []
    for p in paths:
        verdict, why = lanes.judge(lane, p)
        if verdict != "ok":
            bad.append((verdict, p, why))
    for verdict, p, why in bad:
        print(f"  ✗ [{verdict}] {p} — {why}", file=stream)
    print(f"lane={lane} 변경 {len(paths)} · 소유 밖 변경 {len(bad)}", file=stream)
    return len(bad)


# ---------------- 자기 시험(위반을 심은 가짜 diff) ----------------

SELF_TEST_CASES = [
    # (갈래, 경로, 기대 판정)
    ("W0-a", "multiplatform/settings.gradle.kts", "ok"),
    ("W0-a", "multiplatform/testkit/src/commonMain/kotlin/com/yehsung/aingcheck/testkit/mock/MockRouter.kt", "ok"),
    ("W0-a", "multiplatform/core/net/build.gradle.kts", "ok"),
    ("W0-a", ".github/workflows/mp-ci.yml", "ok"),
    ("W0-a", "multiplatform/testkit/src/desktopMain/kotlin/com/yehsung/aingcheck/testkit/golden/Golden.kt", "outside"),
    ("W0-a", "multiplatform/core/foundation/src/commonMain/kotlin/com/yehsung/aingcheck/core/foundation/rng/SplitMix64.kt", "outside"),
    ("W0-a", "multiplatform/core/rules/src/commonMain/kotlin/com/yehsung/aingcheck/core/rules/tetris/TetrisGame.kt", "outside"),
    ("W0-a", "supabase/migrations/20261101000000_x.sql", "forbidden"),
    ("W0-a", "kmp/core/build.gradle.kts", "forbidden"),
    ("W0-a", "contracts/golden/rng/splitmix64.json", "forbidden"),
    ("W0-a", "tools/port-invariants.py", "forbidden"),
    ("W0-a", "backups/2026-10-21-push-send/index.ts", "forbidden"),
    ("W0-a", "xplat/aing-bake/lock.json", "forbidden"),
    ("W0-b", "multiplatform/tools/golden-digest.py", "ok"),
    ("W0-b", "multiplatform/tools/lanes.yml", "reserved"),
    ("W0-b", "multiplatform/testkit/src/desktopMain/kotlin/com/yehsung/aingcheck/testkit/golden/Golden.kt", "ok"),
    ("W1-a", "multiplatform/core/rules/src/commonMain/kotlin/com/yehsung/aingcheck/core/rules/tetris/TetrisGame.kt", "ok"),
    ("W1-a", "multiplatform/core/rules/src/commonMain/kotlin/com/yehsung/aingcheck/core/rules/renju/Renju.kt", "outside"),
    ("W1-a", "contract/golden/tetris/scripted-A.json", "ok"),
    ("W1-a", "contract/golden/_manifest.json", "reserved"),
    ("W1-d", "multiplatform/core/net/src/commonMain/kotlin/com/yehsung/aingcheck/core/net/Service.kt", "ok"),
    ("W1-d", "multiplatform/core/net/build.gradle.kts", "reserved"),
    ("W1-g", "multiplatform/androidApp/src/main/AndroidManifest.xml", "ok"),
    ("W3-b", "multiplatform/androidApp/src/main/res/xml/widget_info.xml", "reserved"),
    ("W2-e", "contract/golden/pause/transitions.json", "ok"),
    ("W2-e", "contract/golden/tetris/duel-resume.json", "outside"),
    ("W3-a", "multiplatform/ui/src/commonMain/kotlin/com/yehsung/aingcheck/ui/screens/messages/MessagesScreen.kt", "ok"),
    ("W3-a", "multiplatform/ui/src/commonMain/kotlin/com/yehsung/aingcheck/ui/screens/me/MeScreen.kt", "outside"),
    ("coordinator", "multiplatform/version.properties", "ok"),
    ("coordinator", "supabase/migrations/x.sql", "forbidden"),
]


def self_test(lanes_path: str) -> int:
    lanes = load_lanes(lanes_path)
    failures = 0
    for lane, path, expected in SELF_TEST_CASES:
        got, why = lanes.judge(lane, path)
        mark = "ok " if got == expected else "BAD"
        if got != expected:
            failures += 1
        print(f"  {mark} {lane:12s} {expected:9s}←{got:9s} {path} {why}")
    # 가짜 diff 전체로 report 경로까지: W0-a 에 위반 셋(옛 경로·남의 소유·골든 로더)을 심으면 빨강 3.
    fake = ["multiplatform/settings.gradle.kts", "supabase/functions/push-send/index.ts",
            "multiplatform/core/rules/src/commonMain/kotlin/com/yehsung/aingcheck/core/rules/tetris/T.kt",
            "multiplatform/testkit/src/commonMain/kotlin/com/yehsung/aingcheck/testkit/golden/Golden.kt"]
    bad = report(lanes, "W0-a", fake)
    if bad != 3:
        failures += 1
        print(f"  BAD 가짜 diff 위반 수 {bad} ≠ 3")
    print(f"self-test: 사례 {len(SELF_TEST_CASES) + 1} · 실패 {failures}")
    return 1 if failures else 0


def main(argv) -> int:
    ap = argparse.ArgumentParser(description="갈래 소유 검사(§8-3)")
    ap.add_argument("--lanes", default=DEFAULT_LANES)
    ap.add_argument("--lane")
    ap.add_argument("--base", default="xplat/main")
    ap.add_argument("--head", default="HEAD")
    ap.add_argument("--names-from")
    ap.add_argument("--include-worktree", action="store_true")
    ap.add_argument("--validate", action="store_true")
    ap.add_argument("--self-test", action="store_true")
    args = ap.parse_args(argv)
    try:
        if args.self_test:
            return self_test(args.lanes)
        lanes = load_lanes(args.lanes)
        if args.validate:
            print(f"lanes.yml 확인: 갈래 {len(lanes.lanes)} · 예약 {len(lanes.reserved)} · 옛 경로 {len(lanes.forbidden)}")
            return 0
        if not args.lane:
            ap.error("--lane 이 필요하다")
        if args.lane not in lanes.lanes:
            print(f"모르는 갈래: {args.lane}", file=sys.stderr)
            return 2
        paths = read_names(args.names_from) if args.names_from else changed_paths(args.base, args.head, args.include_worktree)
        return 1 if report(lanes, args.lane, paths) else 0
    except YamlError as e:
        print(f"lanes.yml 오류: {e}", file=sys.stderr)
        return 2
    except subprocess.CalledProcessError as e:
        print(f"git 실패: {e.stderr}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
