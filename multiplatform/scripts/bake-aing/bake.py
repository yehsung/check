#!/usr/bin/env python3
"""3D 아잉이 굽기 — 인코딩 · 매니페스트 · 잠금(lock.json) · 잠금 대조 · 크기 예산.

엔진(렌더 · 트랙 · 골든)은 Tests/checkTests/AingBakeSuite.swift 가 하고, 이 스크립트는 그 산출물(plan.json + raw/*.rgba.z)을
받아 WebP 로 인코딩하고 multiplatform/assets/aing-bake/ 를 채운다. 진입점은 bake.sh 다.

하위 명령
  finalize   --plan <굽기 출력> --assets <자산 폴더> --repo <저장소>   인코딩 · 매니페스트 · lock.json
  check-lock --repo <저장소>                                           CI(aing-bake-lock): 입력 해시 · 출력 해시가 lock 과 같은가
  sizes      --assets <자산 폴더> --repo <저장소>                      크기 예산(config.json bundles — Windows ≤ 20MB · Android 기본 ≤ 6.9MB)
  compare    <lock A> <lock B>                                         두 lock 의 raw · outputs 다이제스트 대조
  probe-compare <probe.json> <lock.json>                               F-10 탐침 대조 — 같음 · 다름 · 잠금에 없음을 따로 센다
  outside-snapshot --repo <저장소>                                     소유 경로 밖 더러운 파일의 (상태, 경로, sha256) — bake.sh 가 전후를 비교

표준 라이브러리만 쓴다(CI 우분투에서 그대로 돈다). 네트워크를 쓰지 않는다.
"""
import argparse
import concurrent.futures
import glob
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import zlib

ASSETS_REL = "multiplatform/assets/aing-bake"
CONFIG_REL = "multiplatform/scripts/bake-aing/config.json"
REBAKE = "multiplatform/scripts/bake-aing/bake.sh 로 다시 구워라"


# ---------------------------------------------------------------- Swift 주석 걷기
def strip_swift_comments(src):
    """// · /* */(중첩) 주석을 걷는다. 문자열("…" · \"\"\"…\"\"\" · #"…"#)과 보간 \\( … ) 안은 그대로 둔다.
    빈 줄·줄 끝 공백도 지운다 — 설명만 고친 커밋이 굽기를 다시 요구하지 않게(기억 source-contract-tests-need-comment-stripping)."""
    out = []
    n = len(src)

    def code(i, until_paren):
        depth = 0
        while i < n:
            c = src[i]
            if src.startswith("//", i):
                j = src.find("\n", i)
                i = n if j < 0 else j
                continue
            if src.startswith("/*", i):
                d, j = 1, i + 2
                while j < n and d:
                    if src.startswith("/*", j):
                        d, j = d + 1, j + 2
                    elif src.startswith("*/", j):
                        d, j = d - 1, j + 2
                    else:
                        j += 1
                out.append(" ")
                i = j
                continue
            if c == "#" or c == '"':
                j = i
                while j < n and src[j] == "#":
                    j += 1
                if j < n and src[j] == '"':
                    i = string(i, j - i)
                    continue
                out.append(c)
                i += 1
                continue
            if c == "(":
                depth += 1
            elif c == ")":
                if until_paren and depth == 0:
                    return i
                depth -= 1
            out.append(c)
            i += 1
        return i

    def string(i, hashes):
        start = i + hashes
        multi = src.startswith('"""', start)
        quote = '"""' if multi else '"'
        closer = quote + "#" * hashes
        escape = "\\" + "#" * hashes
        out.append(src[i:start + len(quote)])
        j = start + len(quote)
        while j < n:
            if src.startswith(escape, j):
                k = j + len(escape)
                if k < n and src[k] == "(":
                    out.append(src[j:k + 1])
                    j = code(k + 1, True)
                    if j < n:
                        out.append(")")
                        j += 1
                    continue
                out.append(src[j:k + 1])
                j = k + 1
                continue
            if src.startswith(closer, j):
                out.append(closer)
                return j + len(closer)
            if not multi and src[j] == "\n":
                return j
            out.append(src[j])
            j += 1
        return j

    code(0, False)
    lines = [line.rstrip() for line in "".join(out).split("\n")]
    return "\n".join(line for line in lines if line.strip()) + "\n"


def sha256_bytes(data):
    return hashlib.sha256(data).hexdigest()


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


# config.json 가운데 굽기가 읽지 않는 포장 정책(앱에 무엇을 싣나 · 크기 예산). Swift 굽기도 finalize 도 안 본다 — 묶음만 바꿀 때 다시 굽지 않게
# 입력 다이제스트에서 뺀다(8차 spin: Android 기본 묶음에 S 스핀 행을 더함). 정책을 읽는 쪽은 sizes · androidApp 조립 · 묶음 시험이다.
PACKAGING_KEYS = ("bundles",)


def input_digest(repo, rel):
    path = os.path.join(repo, rel)
    if rel == CONFIG_REL:
        with open(path, encoding="utf-8") as f:
            config = json.load(f)
        for key in PACKAGING_KEYS:
            config.pop(key, None)
        return sha256_bytes(json.dumps(config, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8"))
    if rel.endswith(".swift"):
        with open(path, encoding="utf-8") as f:
            return sha256_bytes(strip_swift_comments(f.read()).encode("utf-8"))
    return sha256_file(path)


def expand(repo, patterns):
    files = set()
    for pattern in patterns:
        matches = [m for m in glob.glob(os.path.join(repo, pattern), recursive=True) if os.path.isfile(m)]
        if not matches:
            raise SystemExit(f"입력 패턴이 아무 파일도 안 고른다: {pattern}")
        files.update(os.path.relpath(m, repo).replace(os.sep, "/") for m in matches)
    return sorted(files)


def compute_inputs(repo):
    with open(os.path.join(repo, CONFIG_REL), encoding="utf-8") as f:
        config = json.load(f)
    inputs = {rel: input_digest(repo, rel) for rel in expand(repo, config["inputs"])}
    copied = {rel: sha256_file(os.path.join(repo, rel)) for rel in expand(repo, config["copied"])}
    canonical = json.dumps(inputs, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return config, inputs, copied, "sha256:" + sha256_bytes(canonical)


def dump(obj, path, compact=False):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        if compact:
            json.dump(obj, f, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
        else:
            json.dump(obj, f, ensure_ascii=False, indent=2, sort_keys=True)
        f.write("\n")


def tool_version(cmd):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, check=True).stdout.strip().replace("\n", " ")
    except (OSError, subprocess.CalledProcessError):
        return "unknown"


# ---------------------------------------------------------------- finalize
def encode_one(job):
    src, w, h, dst, args, expect_sha, lossless = job
    with open(src, "rb") as f:
        raw = zlib.decompress(f.read(), -15)
    if len(raw) != w * h * 4:
        raise SystemExit(f"{src}: 길이 {len(raw)} ≠ {w}×{h}×4")
    header = struct_header(w, h)
    digest = hashlib.sha256(w.to_bytes(4, "little") + h.to_bytes(4, "little") + raw).hexdigest()
    if digest != expect_sha:
        raise SystemExit(f"{src}: 원본 다이제스트가 plan 과 다르다")
    with tempfile.TemporaryDirectory() as tmp:
        pam = os.path.join(tmp, "in.pam")
        with open(pam, "wb") as f:
            f.write(header + raw)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        subprocess.run(["cwebp", *args, pam, "-o", dst], check=True)
        if lossless:
            # 무손실은 되읽어 원본과 바이트로 같은지 잰다(골든 · 글리프).
            back = os.path.join(tmp, "back.pam")
            subprocess.run(["dwebp", "-quiet", "-pam", dst, "-o", back], check=True)
            with open(back, "rb") as f:
                data = f.read()
            body = data[data.index(b"ENDHDR\n") + len(b"ENDHDR\n"):]
            if body != raw:
                raise SystemExit(f"{dst}: 무손실 왕복이 원본과 다르다")
    return dst


def struct_header(w, h):
    return f"P7\nWIDTH {w}\nHEIGHT {h}\nDEPTH 4\nMAXVAL 255\nTUPLTYPE RGB_ALPHA\nENDHDR\n".encode("ascii")


def finalize(args):
    plan_dir = os.path.abspath(args.plan)
    assets = os.path.abspath(args.assets)
    repo = os.path.abspath(args.repo)
    with open(os.path.join(plan_dir, "plan.json"), encoding="utf-8") as f:
        plan = json.load(f)
    config, inputs, copied, inputs_hash = compute_inputs(repo)
    if os.path.isdir(assets):
        shutil.rmtree(assets)
    os.makedirs(assets)

    jobs = []
    for image in plan["images"]:
        mode = image["mode"]
        jobs.append((os.path.join(plan_dir, image["src"]), image["w"], image["h"], os.path.join(assets, image["dst"]),
                     config["encode"][mode], image["sha256"], mode == "lossless"))
    workers = max(1, min(8, os.cpu_count() or 1))
    with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as pool:
        for _ in pool.map(encode_one, jobs):
            pass

    files_dir = os.path.join(plan_dir, "files")
    for path in sorted(glob.glob(os.path.join(files_dir, "**", "*"), recursive=True)):
        if not os.path.isfile(path):
            continue
        rel = os.path.relpath(path, files_dir)
        dst = os.path.join(assets, rel)
        if path.endswith(".json"):
            with open(path, encoding="utf-8") as f:
                obj = json.load(f)
            # 큰 표(칸 · 골든)는 줄바꿈 없이, 사람이 읽는 작은 파일은 들여 쓴다. 둘 다 키 정렬.
            dump(obj, dst, compact=os.path.basename(rel).startswith("cells-") or rel.replace(os.sep, "/") == "golden/golden.json")
        else:
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            shutil.copyfile(path, dst)
    for rel, manifest in plan["manifests"].items():
        manifest["bake"]["inputsHash"] = inputs_hash
        # 알파 형식 · 인코딩 역할은 Swift 가 적고(bake.alpha · bake.encoding), 실제 cwebp 인자는 여기서 config 그대로 옮긴다.
        manifest["bake"]["cwebpArgs"] = config["encode"]
        dump(manifest, os.path.join(assets, rel))
    dump(plan["reports"], os.path.join(plan_dir, "reports.json"))

    outputs = {}
    for path in sorted(glob.glob(os.path.join(assets, "**", "*"), recursive=True)):
        if os.path.isfile(path):
            outputs[os.path.relpath(path, assets).replace(os.sep, "/")] = sha256_file(path)
    lock = {
        "bakeFormat": plan["bakeFormat"],
        "inputs": inputs,
        "copied": copied,
        "inputsHash": inputs_hash,
        "tool": {
            "gpu": plan["tool"]["gpu"],
            "xcode": tool_version(["xcodebuild", "-version"]),
            "macos": tool_version(["sw_vers", "-productVersion"]),
            "swift": tool_version(["swift", "--version"]).split(" Target:")[0],
            "cwebp": tool_version(["cwebp", "-version"]).split(" ")[0],
        },
        "raw": plan["raw"],
        "outputs": outputs,
    }
    dump(lock, os.path.join(assets, "lock.json"))
    print(f"[bake] 출력 {len(outputs)} 파일 · raw {len(plan['raw'])} · inputs {len(inputs)} · {inputs_hash}")


# ---------------------------------------------------------------- check-lock (CI)
def check_lock(args):
    repo = os.path.abspath(args.repo)
    assets = os.path.join(repo, ASSETS_REL)
    lock_path = os.path.join(assets, "lock.json")
    if not os.path.isfile(lock_path):
        print(f"[aing-bake-lock] lock.json 이 없다 — {REBAKE}")
        return 1
    with open(lock_path, encoding="utf-8") as f:
        lock = json.load(f)
    _, inputs, copied, inputs_hash = compute_inputs(repo)
    problems = []
    for name, now, then in (("inputs", inputs, lock.get("inputs", {})), ("copied", copied, lock.get("copied", {}))):
        for rel in sorted(set(now) | set(then)):
            if now.get(rel) != then.get(rel):
                state = "새 파일" if rel not in then else ("사라짐" if rel not in now else "바뀜")
                problems.append(f"{name}: {rel} {state}")
    if inputs_hash != lock.get("inputsHash"):
        problems.append(f"inputsHash {lock.get('inputsHash')} → {inputs_hash}")
    present = {}
    for path in sorted(glob.glob(os.path.join(assets, "**", "*"), recursive=True)):
        rel = os.path.relpath(path, assets).replace(os.sep, "/")
        if os.path.isfile(path) and rel != "lock.json":
            present[rel] = sha256_file(path)
    expected = lock.get("outputs", {})
    for rel in sorted(set(present) | set(expected)):
        if present.get(rel) != expected.get(rel):
            state = "잠금에 없는 파일" if rel not in expected else ("빠짐" if rel not in present else "내용이 다르다")
            problems.append(f"outputs: {rel} {state}")
    for rel in sorted(p for p in present if p.endswith("manifest.json")):
        with open(os.path.join(assets, rel), encoding="utf-8") as f:
            if json.load(f).get("bake", {}).get("inputsHash") != lock.get("inputsHash"):
                problems.append(f"{rel}: bake.inputsHash 가 lock 과 다르다")
    if problems:
        print(f"[aing-bake-lock] 실패 {len(problems)}건 — {REBAKE}")
        for p in problems[:200]:
            print("  " + p)
        return 1
    print(f"[aing-bake-lock] 통과 · inputs {len(inputs)} · copied {len(copied)} · outputs {len(present)} · {inputs_hash}")
    return 0


# ---------------------------------------------------------------- sizes
def sizes(args):
    """묶음 크기 — 정의는 config.json 의 bundles(자산 폴더 기준 glob + 저장소 기준 halo glob)."""
    assets = os.path.abspath(args.assets)
    repo = os.path.abspath(args.repo)
    with open(os.path.join(repo, CONFIG_REL), encoding="utf-8") as f:
        bundles = json.load(f)["bundles"]
    report = {}
    over = False
    for name, spec in bundles.items():
        files = set()
        for pattern in spec.get("assets", []):
            files.update(f for f in glob.glob(os.path.join(assets, pattern), recursive=True) if os.path.isfile(f))
        repo_files = set()
        for pattern in spec.get("repo", []):
            repo_files.update(f for f in glob.glob(os.path.join(repo, pattern), recursive=True) if os.path.isfile(f))
        asset_bytes = sum(os.path.getsize(f) for f in files)
        repo_bytes = sum(os.path.getsize(f) for f in repo_files)
        entry = {"bytes": asset_bytes + repo_bytes, "assetBytes": asset_bytes, "repoBytes": repo_bytes,
                 "files": len(files) + len(repo_files)}
        if "budget" in spec:
            entry["budget"] = spec["budget"]
            if entry["bytes"] > spec["budget"]:
                over = True
                entry["over"] = True
        report[name] = entry
    total, count = 0, 0
    for path in glob.glob(os.path.join(assets, "**", "*"), recursive=True):
        if os.path.isfile(path):
            total += os.path.getsize(path)
            count += 1
    report["committedTotal"] = {"bytes": total, "files": count}
    print(json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True))
    if over:
        print("[bake] 크기 예산 초과 — 커밋하지 말고 보고하라")
        return 3
    return 0


# ---------------------------------------------------------------- outside-snapshot
def outside_snapshot(args):
    """소유 경로(ASSETS_REL) 밖의 더러운 파일마다 '상태<TAB>경로<TAB>sha256' 한 줄. 정렬해서 찍는다.

    git status 줄만 비교하면 굽기 전에 이미 수정돼 있던 파일을 굽기가 또 바꿔도 줄이 같아 못 잡는다(W0-d 검증 지적) —
    그래서 내용 해시를 같이 적는다. 지워진 파일은 '-', 폴더(서브모듈 등)는 'dir'."""
    repo = os.path.abspath(args.repo)
    out = subprocess.run(["git", "-C", repo, "status", "--porcelain=v1", "-z", "--untracked-files=all", "--ignore-submodules=none"],
                         capture_output=True, check=True).stdout.decode("utf-8", "surrogateescape")
    parts = out.split("\0")
    entries = []
    i = 0
    while i < len(parts):
        item = parts[i]
        i += 1
        if not item:
            continue
        status, path = item[:2], item[3:]
        paths = [path]
        if status[0] in "RC" or status[1] in "RC":
            paths.append(parts[i])  # -z 에서는 이름 바꾸기의 옛 경로가 다음 칸에 온다
            i += 1
        for rel in paths:
            if rel == ASSETS_REL or rel.startswith(ASSETS_REL + "/"):
                continue
            full = os.path.join(repo, rel)
            if os.path.isfile(full) and not os.path.islink(full):
                digest = sha256_file(full)
            elif os.path.islink(full):
                digest = "link:" + os.readlink(full)
            elif os.path.isdir(full):
                digest = "dir"
            else:
                digest = "-"
            entries.append(f"{status}\t{rel}\t{digest}")
    for line in sorted(entries):
        print(line)
    return 0


# ---------------------------------------------------------------- probe-compare (F-10)
def probe_compare(args):
    """탐침(probe.json · 다른 맥에서 그린 칸의 원본 다이제스트)과 커밋된 lock.json.raw 를 대조한다.
    '잠금에 없음'은 '다름'과 따로 센다 — 잠금에 없는 칸은 재현성과 무관하게 비교할 수 없다(탐침 칸 선택의 결함).
    종료 코드: 0 = 전부 같음, 1 = 다름이 있다, 2 = 잠금에 없는 칸이 있다(다름보다 먼저 고칠 것), 3 = 비교할 칸이 0."""
    with open(args.probe, encoding="utf-8") as f:
        probe = json.load(f)
    with open(args.lock, encoding="utf-8") as f:
        lock = json.load(f).get("raw", {})
    raw = probe.get("raw", {})
    same = sorted(k for k, v in raw.items() if k in lock and lock[k] == v)
    diff = sorted(k for k, v in raw.items() if k in lock and lock[k] != v)
    missing = sorted(k for k in raw if k not in lock)
    print(f"[probe-compare] gpu: {probe.get('gpu', '?')}")
    print(f"[probe-compare] 같음 {len(same)} · 다름 {len(diff)} · 잠금에 없음 {len(missing)} (탐침 {len(raw)}칸)")
    for name, keys in (("같음", same), ("다름", diff), ("잠금에 없음", missing)):
        if keys:
            print(f"  {name}: {keys}")
    if missing:
        return 2
    if diff:
        return 1
    if not same:
        return 3
    return 0


# ---------------------------------------------------------------- compare
def compare(args):
    with open(args.a, encoding="utf-8") as f:
        a = json.load(f)
    with open(args.b, encoding="utf-8") as f:
        b = json.load(f)
    status = 0
    for key in ("raw", "outputs", "inputs"):
        x, y = a.get(key, {}), b.get(key, {})
        diff = sorted(k for k in set(x) | set(y) if x.get(k) != y.get(k))
        print(f"[compare] {key}: {len(x)} vs {len(y)} · 다른 키 {len(diff)}" + (f" (예: {diff[:5]})" if diff else ""))
        if diff:
            status = 1
    return status


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("finalize")
    p.add_argument("--plan", required=True)
    p.add_argument("--assets", required=True)
    p.add_argument("--repo", required=True)
    p = sub.add_parser("check-lock")
    p.add_argument("--repo", required=True)
    p = sub.add_parser("sizes")
    p.add_argument("--assets", required=True)
    p.add_argument("--repo", required=True)
    p = sub.add_parser("compare")
    p.add_argument("a")
    p.add_argument("b")
    p = sub.add_parser("probe-compare")
    p.add_argument("probe")
    p.add_argument("lock")
    p = sub.add_parser("outside-snapshot")
    p.add_argument("--repo", required=True)
    p = sub.add_parser("strip")
    p.add_argument("file")
    args = parser.parse_args()
    if args.cmd == "finalize":
        finalize(args)
        return 0
    if args.cmd == "check-lock":
        return check_lock(args)
    if args.cmd == "sizes":
        return sizes(args)
    if args.cmd == "compare":
        return compare(args)
    if args.cmd == "probe-compare":
        return probe_compare(args)
    if args.cmd == "outside-snapshot":
        return outside_snapshot(args)
    if args.cmd == "strip":
        with open(args.file, encoding="utf-8") as f:
            sys.stdout.write(strip_swift_comments(f.read()))
        return 0
    return 2


if __name__ == "__main__":
    sys.exit(main())
