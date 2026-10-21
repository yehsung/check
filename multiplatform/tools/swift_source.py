"""Swift 소스 낱말 나누기(W0-b) — 주석 걷어내기와 주석 줄 뽑기의 **한 벌뿐인** 구현(C§5.4 "걷어내기 구현은 Python 한 벌").

golden-digest.py(소스 지문)와 port-invariants.py(★·⚠️ 표식)가 같이 쓴다. 두 스크립트는 `python3 -I` 로 돌기 때문에
이 파일을 자기 폴더에서 명시적으로 불러온다(sys.path 에 스크립트 폴더를 직접 넣는다).

다루는 것: `//` 줄 주석 · `/* */` 블록 주석(Swift 는 겹쳐 쓸 수 있다) · 글자 리터럴 `"…"`(이스케이프) · 여러 줄 `\"\"\"…\"\"\"` ·
날 글자 `#"…"#`·`##"…"##`(여러 줄 포함). 글자 리터럴 안의 `//`·`/*`·★ 는 주석이 아니다.
다루지 않는 것: 정규식 리터럴 `/…/`(이 저장소의 Swift 에 없다 — 나오면 나눗셈처럼 읽혀 결과가 보수적으로 틀린다).
"""
from __future__ import annotations

import hashlib
import unicodedata
from dataclasses import dataclass


@dataclass
class Segment:
    kind: str      # "code" · "string" · "line_comment" · "block_comment"
    text: str
    line: int      # 1부터, 조각이 시작하는 줄


def segments(text: str) -> list[Segment]:
    out: list[Segment] = []
    i, n, line = 0, len(text), 1
    buf_start, buf_line = 0, 1

    def flush_code(end: int) -> None:
        if end > buf_start:
            out.append(Segment("code", text[buf_start:end], buf_line))

    while i < n:
        ch = text[i]
        if ch == "/" and i + 1 < n and text[i + 1] == "/":
            flush_code(i)
            j = text.find("\n", i)
            j = n if j < 0 else j
            out.append(Segment("line_comment", text[i:j], line))
            i = j
            buf_start, buf_line = i, line
            continue
        if ch == "/" and i + 1 < n and text[i + 1] == "*":
            flush_code(i)
            start_line, depth, j = line, 1, i + 2
            while j < n and depth > 0:
                if text.startswith("/*", j):
                    depth += 1
                    j += 2
                elif text.startswith("*/", j):
                    depth -= 1
                    j += 2
                else:
                    if text[j] == "\n":
                        line += 1
                    j += 1
            out.append(Segment("block_comment", text[i:j], start_line))
            i = j
            buf_start, buf_line = i, line
            continue
        if ch == '"' or (ch == "#" and _raw_string_start(text, i)):
            flush_code(i)
            start_line = line
            j, line = _scan_string(text, i, line)
            out.append(Segment("string", text[i:j], start_line))
            i = j
            buf_start, buf_line = i, line
            continue
        if ch == "\n":
            line += 1
        i += 1
    flush_code(n)
    return out


def _raw_string_start(text: str, i: int) -> bool:
    j = i
    while j < len(text) and text[j] == "#":
        j += 1
    return j < len(text) and text[j] == '"' and j > i


def _scan_string(text: str, i: int, line: int) -> tuple[int, int]:
    """글자 리터럴 끝(다음 위치)과 끝난 줄 번호."""
    n = len(text)
    hashes = 0
    while i < n and text[i] == "#":
        hashes += 1
        i += 1
    multi = text.startswith('"""', i)
    i += 3 if multi else 1
    close = ('"""' if multi else '"') + "#" * hashes
    escape = "\\" + "#" * hashes
    while i < n:
        if text.startswith(escape, i):
            i += len(escape)
            if i < n:
                if text[i] == "\n":
                    line += 1
                if text[i] == "(" and hashes == 0:
                    i, line = _skip_interpolation(text, i, line)
                    continue
                i += 1
            continue
        if text.startswith(close, i):
            return i + len(close), line
        if text[i] == "\n":
            if not multi and hashes == 0:
                return i, line   # 닫히지 않은 한 줄 글자 — 줄 끝에서 끊는다(보수적)
            line += 1
        i += 1
    return n, line


def _skip_interpolation(text: str, i: int, line: int) -> tuple[int, int]:
    """`\\(` 다음 위치에서 짝 괄호까지(안의 글자 리터럴은 건너뛴다)."""
    depth, n = 0, len(text)
    while i < n:
        ch = text[i]
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
            if depth == 0:
                return i + 1, line
        elif ch == '"':
            i, line = _scan_string(text, i, line)
            continue
        elif ch == "\n":
            line += 1
        i += 1
    return n, line


def strip_comments(text: str) -> str:
    """주석을 걷어낸 코드(+글자 리터럴). 줄 끝 공백을 지우고 빈 줄을 뺀다 — 주석·빈 줄만 바꾼 커밋은 지문이 그대로다."""
    kept = "".join(seg.text if seg.kind in ("code", "string") else " " for seg in segments(text))
    lines = [ln.rstrip() for ln in kept.split("\n")]
    return "\n".join(ln for ln in lines if ln.strip()) + "\n"


def stripped_sha256(text: str) -> str:
    return hashlib.sha256(strip_comments(text).encode("utf-8")).hexdigest()


MARKERS = ("★", "⚠️", "⚠")


def has_marker(text: str) -> bool:
    return any(m in text for m in MARKERS)


def comment_lines(text: str) -> list[tuple[int, str, bool]]:
    """주석 줄 목록: (줄 번호, 주석 글자, 줄 전체가 주석인가). 블록 주석은 줄마다 나눈다."""
    out: list[tuple[int, str, bool]] = []
    src_lines = text.split("\n")
    for seg in segments(text):
        if seg.kind == "line_comment":
            whole = src_lines[seg.line - 1].strip().startswith("//")
            out.append((seg.line, seg.text, whole))
        elif seg.kind == "block_comment":
            for k, part in enumerate(seg.text.split("\n")):
                ln = seg.line + k
                whole = src_lines[ln - 1].strip().startswith(("/*", "*")) or k > 0
                out.append((ln, part, whole))
    return out


def normalize_comment(text: str) -> str:
    """ID 해시용 본문: 주석 기호를 걷고 공백을 접고 NFC."""
    t = text.strip()
    for prefix in ("///", "//", "/**", "/*", "*/", "*"):
        if t.startswith(prefix):
            t = t[len(prefix):]
            break
    if t.endswith("*/"):
        t = t[:-2]
    return unicodedata.normalize("NFC", " ".join(t.split()))
