#!/usr/bin/env python3
"""갈래 소유 검사(§8-3, W0-a). 실행은 `python3 -I multiplatform/tools/lane-ownership.py …`.

브랜치 diff(기준...머리)의 경로마다 판정한다:
  0. 닫힌 갈래(lanes.yml closed — 예: W0 통합 뒤의 W0-a)                        → 빨강
  1. 옛 경로(§8-1: 꼭대기 xplat/ kmp/ contracts/ tools/ backups/ supabase/)  → 빨강
  2. 예약 경로인데 이 갈래가 예약 목록에 없음                                   → 빨강
  3. 이 갈래 owns 글롭 밖이거나 excludes 에 걸림                                 → 빨강
빨강이 하나라도 있으면 종료 코드 1. 마지막 줄에 "소유 밖 변경 N" 을 찍는다(완료 보고에 붙인다).

  --lane W0-a [--base xplat/main] [--head HEAD]   git diff --no-renames --name-only base...head
  --lane W0-a --names-from FILE                    경로 목록 파일(한 줄에 하나, '#' 주석) — 가짜 diff 로 시험할 때
  --include-worktree                               커밋 안 된 변경(git status)도 더한다
  --upstream origin/main                           기준선 병합(main → xplat) 몫을 뺀다: merge-base(base, upstream)..upstream 에서
                                                   바뀐 경로 가운데 머리의 내용이 upstream 과 바이트까지 같은 것만 뺀다(그 경로는 main 의
                                                   변경이지 이 브랜치의 변경이 아니다). main 이 안 바꾼 경로를 main 판으로 되돌리면 그대로
                                                   센다(xplat 변경을 몰래 되돌리는 것은 빨강). xplat/main 이 main 을 따라잡았으면 뺄 것이 0.
  --resolve-branch xplat/w1-a                      브랜치 이름 → 갈래(CI 가 쓴다). xplat/main·xplat/w<N>-int·xplat/int-<x> → coordinator,
                                                   xplat/w<N>-<x>[숫자] → 그 갈래. xplat/ 인데 갈래로 안 풀리면 종료 2(빨강).
                                                   xplat/ 밖 브랜치(main 등)는 빈 줄 · 종료 0(갈래 소유 검사 대상 아님)
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
        closed = data.get("closed") or []
        if not isinstance(closed, list):
            raise YamlError("closed 는 갈래 이름 목록이어야 한다")
        self.closed = set(closed)
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
            if allowed & self.closed:
                raise YamlError(f"reserved '{glob}' 에 닫힌 갈래가 있다: {sorted(allowed & self.closed)}")
        unknown_closed = self.closed - set(self.lanes)
        if unknown_closed or "coordinator" in self.closed:
            raise YamlError(f"closed 에 없는 갈래·조정자: {sorted(unknown_closed | ({'coordinator'} & self.closed))}")

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
        """(판정, 이유). 판정은 ok|closed|forbidden|reserved|outside."""
        if lane not in self.lanes:
            raise KeyError(lane)
        if lane in self.closed:
            return "closed", "닫힌 갈래 — 후속 변경은 조정자 경유(xplat/w<N>-int)"
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


BRANCH_LANE = re.compile(r"xplat/w(\d+)-([a-z])(\d*)")
# 통합 브랜치(조정자 대리): xplat/main · 웨이브 통합 xplat/w<N>-int · 묶음 통합 xplat/int-<소문자로 시작하는 이름>(3차 묶음부터).
INTEGRATION_BRANCH = re.compile(r"xplat/(?:main|w\d+-int|int-[a-z][a-z0-9]*)")


def resolve_branch(lanes: Lanes, branch: str):
    """브랜치 → 갈래 이름. xplat/ 밖이면 None(검사 대상 아님). xplat/ 인데 못 풀면 ValueError."""
    if not branch.startswith("xplat/"):
        return None
    if INTEGRATION_BRANCH.fullmatch(branch):
        return "coordinator"
    m = BRANCH_LANE.fullmatch(branch)
    if m:
        lane = f"W{m.group(1)}-{m.group(2)}{m.group(3)}"
        if lane in lanes.lanes:
            return lane
        # 같은 갈래를 다시 돌릴 때 옛 브랜치를 덮지 않으려고 숫자 꼬리를 붙인다(5차 W0-f ③ = xplat/w0-f3, G §8-16).
        # 그 이름의 갈래(W3-c1 같은)가 없고 꼬리를 뗀 갈래가 있을 때만 뗀다 — 소유 검사는 뗀 갈래의 owns 그대로다.
        base = f"W{m.group(1)}-{m.group(2)}"
        if m.group(3) and base in lanes.lanes:
            return base
        raise ValueError(f"{branch}: lanes.yml 에 갈래 {lane} 가 없다")
    raise ValueError(f"{branch}: 갈래로 풀리지 않는 xplat/ 브랜치(xplat/w<N>-<갈래> · xplat/w<N>-int · xplat/int-<x> · xplat/main 만)")


def load_lanes(path: str) -> Lanes:
    with open(path, encoding="utf-8") as f:
        return Lanes(parse_yaml(f.read()))


# ---------------- git ----------------

def repo_root() -> str:
    return subprocess.run(["git", "rev-parse", "--show-toplevel"], check=True, capture_output=True, text=True, cwd=HERE).stdout.strip()


def _git_names(root: str, *args: str):
    out = subprocess.run(["git", "diff", "--no-renames", "--name-only", *args],
                         check=True, capture_output=True, text=True, cwd=root).stdout.splitlines()
    return set(p for p in out if p)


def split_upstream(changed, upstream_changed, differs_from_upstream):
    """기준선 병합 몫 가르기(순수 함수). (남길 경로, 뺄 경로).

    뺀다 = upstream 이 (base 와 갈라진 뒤) 바꾼 경로 ∧ 머리 내용이 upstream 과 같다.
    남긴다 = 그 밖 전부 — 특히 upstream 이 안 바꾼 경로를 upstream 판으로 되돌린 것(xplat 변경을 지운 것)은 남긴다.
    """
    dropped = {p for p in changed if p in upstream_changed and p not in differs_from_upstream}
    return sorted(set(changed) - dropped), sorted(dropped)


def changed_paths(base: str, head: str, include_worktree: bool, upstream: str | None = None):
    root = repo_root()
    paths = _git_names(root, f"{base}...{head}")
    if upstream:
        mb = subprocess.run(["git", "merge-base", base, upstream],
                            check=True, capture_output=True, text=True, cwd=root).stdout.strip()
        kept, dropped = split_upstream(paths, _git_names(root, mb, upstream), _git_names(root, upstream, head))
        print(f"upstream {upstream}: merge-base({base}, {upstream})={mb[:12]} · upstream 그대로인 기준선 병합 몫 {len(dropped)} 경로는 뺐다")
        paths = set(kept)
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
    # W0-a 는 W0 통합에서 닫혔다 — 자기 자리였던 파일도 빨강(후속은 조정자 경유).
    ("W0-a", "multiplatform/settings.gradle.kts", "closed"),
    ("W0-a", "multiplatform/testkit/src/commonMain/kotlin/com/yehsung/aingcheck/testkit/mock/MockRouter.kt", "closed"),
    ("coordinator", "multiplatform/settings.gradle.kts", "ok"),
    ("coordinator", "multiplatform/core/net/build.gradle.kts", "ok"),
    ("coordinator", ".github/workflows/mp-ci.yml", "ok"),
    ("coordinator", "multiplatform/androidApp/src/main/kotlin/com/yehsung/aingcheck/android/http/HttpEngineFactory.kt", "ok"),
    ("coordinator", "supabase/migrations/20261101000000_x.sql", "forbidden"),
    ("coordinator", "kmp/core/build.gradle.kts", "forbidden"),
    ("coordinator", "contracts/golden/rng/splitmix64.json", "forbidden"),
    ("coordinator", "tools/port-invariants.py", "forbidden"),
    ("coordinator", "backups/2026-10-21-push-send/index.ts", "forbidden"),
    ("coordinator", "xplat/aing-bake/lock.json", "forbidden"),
    # W0-e 의 탐침은 자기 완결 빌드라 그 build.gradle.kts 는 이 빌드의 모듈 예약에 들지 않는다(W0 통합에서 고침).
    ("W0-e", "multiplatform/spikes/windows/build.gradle.kts", "ok"),
    ("W0-e", "multiplatform/scripts/vm/vm.sh", "ok"),
    ("W0-e", "multiplatform/build.gradle.kts", "reserved"),
    ("W0-f", "multiplatform/scripts/emu.sh", "ok"),
    ("W0-f", "multiplatform/scripts/gate-full.sh", "reserved"),
    ("W5-a", "multiplatform/character/build.gradle.kts", "reserved"),
    ("W2-f", "multiplatform/feature/phone/build.gradle.kts", "reserved"),
    # 조정자 전용 예약(뼈대·HTTP 팩토리·도구 표)은 열린 갈래가 건드리면 빨강이다.
    ("W3-a", "multiplatform/androidApp/src/main/kotlin/com/yehsung/aingcheck/android/http/HttpEngineFactory.kt", "reserved"),
    ("W3-c1", "multiplatform/desktopApp/src/main/kotlin/com/yehsung/aingcheck/desktop/http/HttpEngineFactory.kt", "reserved"),
    ("W4-c", "multiplatform/ui/src/commonMain/kotlin/com/yehsung/aingcheck/ui/scaffold/ScaffoldProbe.kt", "reserved"),
    ("W1-a", "multiplatform/tools/lanes.yml", "reserved"),
    # W1-e·W1-f·W1-g·W0-b 는 3차 통합(xplat/int-b)에서 닫혔다 — 자기 자리였던 파일도 빨강, 후속은 조정자 경유.
    ("W0-b", "multiplatform/tools/golden-digest.py", "closed"),
    ("W0-b", "multiplatform/testkit/src/desktopMain/kotlin/com/yehsung/aingcheck/testkit/golden/Golden.kt", "closed"),
    ("W0-b", "contract/golden/_manifest.json", "closed"),
    ("W1-e", "multiplatform/ui/src/commonMain/kotlin/com/yehsung/aingcheck/ui/theme/AingTheme.kt", "closed"),
    ("W1-e", "multiplatform/ui/src/commonMain/composeResources/font/x.ttf", "closed"),
    ("W1-f", "multiplatform/desktopApp/src/main/kotlin/com/yehsung/aingcheck/desktop/platform/windows/tray/Tray.kt", "closed"),
    ("W1-f", "multiplatform/desktopApp/src/main/kotlin/com/yehsung/aingcheck/desktop/AppGraph.kt", "closed"),
    ("W1-g", "multiplatform/androidApp/src/main/kotlin/com/yehsung/aingcheck/android/shell/MainActivity.kt", "closed"),
    ("W1-g", "multiplatform/androidApp/src/main/kotlin/com/yehsung/aingcheck/android/nav/NavGraph.kt", "closed"),
    ("coordinator", "multiplatform/tools/golden-digest.py", "ok"),
    ("coordinator", "multiplatform/testkit/src/desktopMain/kotlin/com/yehsung/aingcheck/testkit/golden/Golden.kt", "ok"),
    ("coordinator", "multiplatform/ui/src/commonMain/composeResources/font/x.ttf", "ok"),
    ("coordinator", "multiplatform/desktopApp/src/main/kotlin/com/yehsung/aingcheck/desktop/AppGraph.kt", "ok"),
    ("W1-a", "multiplatform/core/rules/src/commonMain/kotlin/com/yehsung/aingcheck/core/rules/tetris/TetrisGame.kt", "ok"),
    ("W1-a", "multiplatform/core/rules/src/commonMain/kotlin/com/yehsung/aingcheck/core/rules/renju/Renju.kt", "outside"),
    ("W1-a", "contract/golden/tetris/scripted-A.json", "ok"),
    ("W1-a", "contract/golden/_manifest.json", "ok"),        # 골든 갈래는 생성물 목록·지문을 다시 만들어 커밋한다(lanes.yml reserved)
    ("W3-a", "contract/golden/_manifest.json", "reserved"),  # 골든 없는 갈래는 여전히 못 쓴다
    ("W2-e", "contract/golden/_digests.json", "ok"),
    ("W1-d", "multiplatform/core/net/src/commonMain/kotlin/com/yehsung/aingcheck/core/net/Service.kt", "ok"),
    ("W1-d", "multiplatform/core/net/build.gradle.kts", "reserved"),
    # AndroidManifest.xml 은 W1-g 병합 뒤 조정자만(lanes.yml reserved). 남이 쓰면 예약 빨강, W1-g 는 닫힘 빨강.
    ("W1-g", "multiplatform/androidApp/src/main/AndroidManifest.xml", "closed"),
    ("W3-b", "multiplatform/androidApp/src/main/AndroidManifest.xml", "reserved"),
    ("coordinator", "multiplatform/androidApp/src/main/AndroidManifest.xml", "ok"),
    ("W3-a", "multiplatform/androidApp/src/main/kotlin/com/yehsung/aingcheck/android/nav/NavGraph.kt", "reserved"),
    ("W4-c", "multiplatform/ui/src/commonMain/composeResources/drawable/gacha.png", "reserved"),
    ("W3-b", "multiplatform/androidApp/src/main/res/xml/widget_info.xml", "reserved"),
    ("W2-e", "contract/golden/pause/transitions.json", "ok"),
    ("W2-e", "contract/golden/tetris/duel-resume.json", "outside"),
    ("W3-a", "multiplatform/ui/src/commonMain/kotlin/com/yehsung/aingcheck/ui/screens/messages/MessagesScreen.kt", "ok"),
    ("W3-a", "multiplatform/ui/src/commonMain/kotlin/com/yehsung/aingcheck/ui/screens/me/MeScreen.kt", "outside"),
    ("coordinator", "multiplatform/version.properties", "ok"),
    ("coordinator", "supabase/migrations/x.sql", "forbidden"),
    # W0-c·W0-d 는 기준선 통합(xplat/int-a)에서 닫혔다 — 자기 자리였던 파일도 빨강, 다시 굽기·서버 ① 시험 손질은 조정자 경유.
    ("W0-c", "Tests/checkTests/XplatServerMigrationTests.swift", "closed"),
    ("W0-c", "contract/push/payloads/message.json", "closed"),
    ("W0-d", "multiplatform/assets/aing-bake/lock.json", "closed"),
    ("W0-d", "Tests/checkTests/AingBakeSuite.swift", "closed"),
    ("coordinator", "Tests/checkTests/XplatServerMigrationTests.swift", "ok"),
    ("coordinator", "multiplatform/assets/aing-bake/lock.json", "ok"),
    ("coordinator", "multiplatform/scripts/bake-aing/bake.sh", "ok"),
    ("coordinator", ".github/workflows/mp-bake.yml", "ok"),
    ("coordinator", "Sources/check/CheckMessageView.swift", "outside"),
    # 5차 기준선 통합(xplat/int-d, G §8-16): 새 골든 폴더 crossy(W1-a) · missions·gift(W1-c) · messages(W2-b), W1-d 의 G6 덤프기 자리.
    ("W1-a", "contract/golden/crossy/scripted-A.json", "ok"),
    ("W1-b", "contract/golden/crossy/scripted-A.json", "outside"),
    ("W1-c", "contract/golden/missions/daily-rollover.json", "ok"),
    ("W1-c", "contract/golden/gift/claim-outcome.json", "ok"),
    ("W1-d", "contract/golden/gift/claim-outcome.json", "outside"),
    ("W2-b", "contract/golden/messages/sort.json", "ok"),
    ("W2-b", "Tests/CheckMobileKitTests/GoldenExport/messages/GoldenExportMessages.swift", "ok"),
    ("W2-b", "contract/golden/_manifest.json", "ok"),
    ("W2-c", "contract/golden/_manifest.json", "reserved"),  # 골든 폴더가 없는 스토어 갈래는 여전히 못 쓴다
    ("W2-d", "contract/golden/messages/sort.json", "outside"),
    ("W1-d", "multiplatform/testkit/src/desktopMain/kotlin/com/yehsung/aingcheck/testkit/dump/DecodeDump.kt", "ok"),
    ("W1-d", "multiplatform/testkit/src/desktopMain/kotlin/com/yehsung/aingcheck/testkit/golden/Golden.kt", "outside"),
    ("W1-d", "multiplatform/testkit/build.gradle.kts", "reserved"),
]

# 기준선 병합 몫 가르기(--upstream) 사례: (경로, upstream 이 바꿈, 머리가 upstream 과 다름, 기대: 뺌|남김).
UPSTREAM_CASES = [
    ("Sources/check/CheckMessageView.swift", True, False, "뺌"),     # main 이 바꾸고 머리가 그대로 가져옴(0.3.62 병합)
    ("Package.swift", True, True, "남김"),                            # main 도 xplat 도 바꿈 — 합친 내용은 이 브랜치 변경
    ("Sources/check/WorkTimerStore.swift", False, False, "남김"),     # main 이 안 바꾼 경로를 main 판으로 되돌림 — xplat 변경 지우기
    ("multiplatform/settings.gradle.kts", False, True, "남김"),       # xplat 만의 경로
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
    # 가짜 diff 전체로 report 경로까지: W1-a 에 위반 셋(옛 경로·남의 소유·예약 빌드 파일)을 심으면 빨강 3.
    fake = ["multiplatform/core/rules/src/commonMain/kotlin/com/yehsung/aingcheck/core/rules/tetris/T.kt",
            "supabase/functions/push-send/index.ts",
            "multiplatform/core/rules/src/commonMain/kotlin/com/yehsung/aingcheck/core/rules/renju/R.kt",
            "multiplatform/core/rules/build.gradle.kts"]
    bad = report(lanes, "W1-a", fake)
    if bad != 3:
        failures += 1
        print(f"  BAD 가짜 diff 위반 수 {bad} ≠ 3")
    # 기준선 병합 몫 가르기 — 순수 함수 사례 + report 까지(조정자: main 몫을 빼면 0, 되돌리기는 빨강 1).
    paths = [c[0] for c in UPSTREAM_CASES]
    up_changed = {c[0] for c in UPSTREAM_CASES if c[1]}
    differs = {c[0] for c in UPSTREAM_CASES if c[2]}
    kept, dropped = split_upstream(paths, up_changed, differs)
    for path, _, _, expected in UPSTREAM_CASES:
        got = "뺌" if path in dropped else "남김"
        mark = "ok " if got == expected else "BAD"
        if got != expected:
            failures += 1
        print(f"  {mark} upstream {expected}←{got} {path}")
    bad = report(lanes, "coordinator", kept)
    if bad != 1:
        failures += 1
        print(f"  BAD upstream 가른 뒤 조정자 위반 수 {bad} ≠ 1(되돌린 Sources 하나)")
    # 브랜치 → 갈래(CI lane-tools). 못 푸는 xplat/ 브랜치는 빨강이어야 한다(W0 검증: 전엔 notice 만 남기고 초록).
    branch_cases = [
        ("xplat/w0-a", "W0-a"), ("xplat/w1-g", "W1-g"), ("xplat/w3-c1", "W3-c1"),
        ("xplat/w0-int", "coordinator"), ("xplat/w1-int", "coordinator"), ("xplat/main", "coordinator"),
        ("main", None), ("feature/x", None),
        ("xplat/w0-a-fix", ValueError), ("xplat/W0-a", ValueError), ("xplat/w9-z", ValueError),
        ("xplat/w3-c", ValueError), ("xplat/foo", ValueError),
        ("xplat/w0-f3", "W0-f"), ("xplat/w1-c2", "W1-c"), ("xplat/w3-c9", ValueError), ("xplat/w0-f3-x", ValueError),
        ("xplat/int-a", "coordinator"), ("xplat/int-b2", "coordinator"),
        ("xplat/int", ValueError), ("xplat/int-", ValueError), ("xplat/int-A", ValueError), ("xplat/int-a-fix", ValueError),
    ]
    for branch, expected in branch_cases:
        try:
            got = resolve_branch(lanes, branch)
        except ValueError:
            got = ValueError
        mark = "ok " if got == expected else "BAD"
        if got != expected:
            failures += 1
        print(f"  {mark} 브랜치 {branch:16s} → {getattr(got, '__name__', got)}")
    print(f"self-test: 사례 {len(SELF_TEST_CASES) + 1 + len(UPSTREAM_CASES) + 1 + len(branch_cases)} · 실패 {failures}")
    return 1 if failures else 0


def main(argv) -> int:
    ap = argparse.ArgumentParser(description="갈래 소유 검사(§8-3)")
    ap.add_argument("--lanes", default=DEFAULT_LANES)
    ap.add_argument("--lane")
    ap.add_argument("--base", default="xplat/main")
    ap.add_argument("--head", default="HEAD")
    ap.add_argument("--names-from")
    ap.add_argument("--include-worktree", action="store_true")
    ap.add_argument("--upstream", help="기준선 병합 몫을 뺄 upstream(예: origin/main) — --upstream 설명은 모듈 머리말")
    ap.add_argument("--validate", action="store_true")
    ap.add_argument("--self-test", action="store_true")
    ap.add_argument("--resolve-branch")
    args = ap.parse_args(argv)
    try:
        if args.self_test:
            return self_test(args.lanes)
        lanes = load_lanes(args.lanes)
        if args.validate:
            print(f"lanes.yml 확인: 갈래 {len(lanes.lanes)} · 예약 {len(lanes.reserved)} · 옛 경로 {len(lanes.forbidden)} · 닫힘 {len(lanes.closed)}")
            return 0
        if args.resolve_branch is not None:
            try:
                lane = resolve_branch(lanes, args.resolve_branch)
            except ValueError as e:
                print(f"갈래로 풀리지 않는다: {e}", file=sys.stderr)
                return 2
            print(lane or "")
            return 0
        if not args.lane:
            ap.error("--lane 이 필요하다")
        if args.lane not in lanes.lanes:
            print(f"모르는 갈래: {args.lane}", file=sys.stderr)
            return 2
        if args.names_from and args.upstream:
            ap.error("--names-from 과 --upstream 은 함께 쓰지 않는다(가짜 diff 에는 upstream 이 없다)")
        paths = read_names(args.names_from) if args.names_from else changed_paths(args.base, args.head, args.include_worktree, args.upstream)
        return 1 if report(lanes, args.lane, paths) else 0
    except YamlError as e:
        print(f"lanes.yml 오류: {e}", file=sys.stderr)
        return 2
    except subprocess.CalledProcessError as e:
        print(f"git 실패: {e.stderr}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
