# 원본: 없음 (W0-f ③ 측정 덤프의 정규 지문 — 시간 칸(millis·totalMillis)과 단언 칸(probeProblems)을 빼고 키를 정렬한 JSON 의 sha256)
# 사용: python3 -I canon.py <덤프.json>...   → "<sha256>  <파일>" 줄. 같은 기기 판·같은 표면 다시 재도 같은 값이 나온다.
import hashlib
import json
import sys

DROP = {"millis", "totalMillis", "probeProblems"}


def strip(o):
    if isinstance(o, dict):
        return {k: strip(v) for k, v in o.items() if k not in DROP}
    if isinstance(o, list):
        return [strip(v) for v in o]
    return o


for path in sys.argv[1:]:
    with open(path, encoding="utf-8") as f:
        data = strip(json.load(f))
    blob = json.dumps(data, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    print(f"{hashlib.sha256(blob).hexdigest()}  {path}")
