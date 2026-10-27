# 원본: 없음 (W0-f ③ 대조기 — contract/README §6-1 의 수치를 낸 원문. Swift 표 · JVM 덤프 · ART 덤프(API 별)를 칸별로 대조해 요약 JSON 을 낸다)
# 사용: python3 -I compare.py <w0b-probe 폴더> <jvm.json> <이름=art.json>... > summary.json
import json
import sys

SURR = range(0xD800, 0xE000)


def expand(ranges):
    out = [None] * 0x110000
    nxt = 0
    for tok in ranges.split(','):
        span, klass = tok.split(':')
        lo, hi = (int(x, 16) for x in span.split('-'))
        assert lo == nxt, f"구간 끊김 {tok}"
        nxt = hi + 1
        for cp in range(lo, hi + 1):
            out[cp] = klass
    assert nxt == 0x110000, "끝까지 안 덮음"
    return out


FIELDS = [("gc", 0, 2), ("ws", 2, 3), ("visible", 3, 4), ("nfcStable", 4, 5)]


def field_diff(a, b, examples=6):
    counts = {f: 0 for f, _, _ in FIELDS}
    samples = {f: [] for f, _, _ in FIELDS}
    unassigned_gap = {"aCnOnly": 0, "bCnOnly": 0, "bothAssignedDiffer": 0}
    for cp in range(0x110000):
        if cp in SURR:
            continue
        x, y = a[cp], b[cp]
        if x == y:
            continue
        for f, s, e in FIELDS:
            if x[s:e] != y[s:e]:
                counts[f] += 1
                if len(samples[f]) < examples:
                    samples[f].append(f"U+{cp:04X} {x[s:e]}/{y[s:e]}")
        if x[0:2] != y[0:2]:
            if x[0:2] == "Cn":
                unassigned_gap["aCnOnly"] += 1
            elif y[0:2] == "Cn":
                unassigned_gap["bCnOnly"] += 1
            else:
                unassigned_gap["bothAssignedDiffer"] += 1
    return {"counts": counts, "gcSplit": unassigned_gap, "samples": samples}


def main():
    probe_dir, jvm_path = sys.argv[1], sys.argv[2]
    arts = [a.split('=', 1) for a in sys.argv[3:]]
    load = lambda n: json.load(open(f"{probe_dir}/{n}.json"))
    swift_scal = expand(",".join(c["ranges"] for c in load("text-scalars")["cases"]))
    swift_g = {c["id"]: ",".join(str(x) for x in c["clusters"]) for c in load("graphemes")["cases"]}
    swift_g_cps = {c["id"]: c["cps"] for c in load("graphemes")["cases"]}
    swift_n = {c["id"]: c["nfc"] for c in load("nfc")["cases"]}
    swift_n_in = {c["id"]: c["cps"] for c in load("nfc")["cases"]}

    runs = [("jvm", json.load(open(jvm_path)))] + [(n, json.load(open(p))) for n, p in arts]
    scal = {}
    for name, d in runs:
        for gname, g in d["scalars"].items():
            if isinstance(g, dict) and "ranges" in g:
                scal[f"{name}:{gname}"] = expand(g["ranges"])
    out = {"runtimes": {}, "scalars": {}, "graphemes": {}, "nfc": {}, "kst": {}, "pow": {}}
    for name, d in runs:
        out["runtimes"][name] = {"env": d["env"], "art": d.get("art")}

    # 글자 분류: 각 런타임 vs Swift, ART vs JVM, ART 끼리
    jvm_key = "jvm:javaCharacter"
    for k, arr in scal.items():
        out["scalars"][f"{k} vs swift"] = field_diff(swift_scal, arr)
        if k != jvm_key:
            out["scalars"][f"{k} vs {jvm_key}"] = field_diff(scal[jvm_key], arr)
    art_keys = [k for k in scal if not k.startswith("jvm:")]
    for i in range(len(art_keys)):
        for j in range(i + 1, len(art_keys)):
            out["scalars"][f"{art_keys[i]} vs {art_keys[j]}"] = field_diff(scal[art_keys[i]], scal[art_keys[j]])

    # 그래핌
    gruns = {}
    for name, d in runs:
        for bname, b in d["graphemes"].items():
            if isinstance(b, dict) and "clusters" in b:
                gruns[f"{name}:{bname}"] = b["clusters"]
    for k, cl in gruns.items():
        vs_swift = sorted(i for i in swift_g if cl.get(i) != swift_g[i])
        entry = {"vsSwift": len(vs_swift), "vsSwiftIds": [f"{i}[{swift_g_cps[i]}] swift={swift_g[i]} got={cl.get(i)}" for i in vs_swift]}
        if not k.startswith("jvm:"):
            ref = gruns["jvm:javaText"]
            vs_jvm = sorted(i for i in swift_g if cl.get(i) != ref.get(i))
            entry["vsJvmJavaText"] = len(vs_jvm)
            entry["vsJvmIds"] = vs_jvm
        out["graphemes"][k] = entry

    # NFC
    nruns = {}
    for name, d in runs:
        for nname, b in d["nfc"].items():
            if isinstance(b, dict) and "results" in b:
                nruns[f"{name}:{nname}"] = b["results"]
    for k, res in nruns.items():
        vs_swift = sorted(i for i in swift_n if res.get(i) != swift_n[i])
        entry = {"vsSwift": len(vs_swift), "vsSwiftIds": [f"{i} in={swift_n_in[i]} swift={swift_n[i]} got={res.get(i)}" for i in vs_swift]}
        if not k.startswith("jvm:"):
            ref = nruns["jvm:javaText"]
            vs_jvm = sorted(i for i in swift_n if res.get(i) != ref.get(i))
            entry["vsJvmJavaText"] = len(vs_jvm)
            entry["vsJvmIds"] = [f"{i} in={swift_n_in[i]} jvm={ref.get(i)} got={res.get(i)}" for i in vs_jvm]
        out["nfc"][k] = entry

    for name, d in runs:
        k = d["kst"]
        out["kst"][name] = {x: k.get(x) for x in ("n", "mondayCompared", "vsSwift", "ids", "samples", "error")}
        p = d["pow3"]
        g = d["gravity"]
        out["pow"][name] = {
            **{x: p.get(x) for x in ("n", "mathVsDarwin", "strictVsDarwin", "refVsDarwin", "mathVsStrict", "mathDigest",
                                      "strictDigest", "integrityFailures", "edgesN", "edgesMathVsDarwin", "edgesStrictVsDarwin", "error")},
            "gravityMathVsDarwin": g.get("mathVsDarwin"), "gravityStrictVsDarwin": g.get("strictVsDarwin"),
            "gravityBaseMismatch": g.get("baseBitsMismatch"),
        }
    jvm_pow = out["pow"]["jvm"]
    for name, _ in runs[1:]:
        out["pow"][name]["mathDigestEqualsJvmMath"] = out["pow"][name]["mathDigest"] == jvm_pow["mathDigest"]
        out["pow"][name]["strictDigestEqualsJvmStrict"] = out["pow"][name]["strictDigest"] == jvm_pow["strictDigest"]
    json.dump(out, sys.stdout, ensure_ascii=False, indent=1)


main()
