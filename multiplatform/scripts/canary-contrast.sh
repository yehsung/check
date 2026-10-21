#!/usr/bin/env bash
# 카나리아 대조(A-X15·X16): 봉인 **없이** NetworkCanaryTest 를 돌리면 빨강이어야 한다 — 그것도 '봉인이 새었다'는 이유로만.
#
#   multiplatform/scripts/canary-contrast.sh        # 봉인 밖에서 부른다(CI: 봉인 게이트 다음 단계, 맥: 손으로)
#
# 통과 조건(셋 다):
#   ① Gradle 종료 코드 ≠ 0
#   ② 카나리아 결과 XML 에 시험이 돌았고 단언 실패(<failure>)가 있으며 그 메시지가 '봉인이 새고 있다' 다
#   ③ 시험 출력(system-out)에 `AINGCHECK-CANARY … OPEN` 이 있다(바깥 연결이 실제로 열렸다)
# 컴파일 실패·의존 누락·시험을 못 찾음·건너뜀으로 빨개진 것은 대조 실패(종료 1)다 — W0 검증: 전엔 rc≠0 이면 무조건 통과였다.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MP="$(cd "$HERE/.." && pwd)"

die() { echo "canary-contrast: $*" >&2; exit 2; }
[[ "${AINGCHECK_GATE_INNER:-}" != "1" ]] || die "봉인 안에서 부르지 않는다 — 대조는 봉인 밖 실행이다"

PY=""
for c in python3 python; do
  if command -v "$c" >/dev/null 2>&1 && "$c" -c 'import sys; sys.exit(0 if sys.version_info[0] == 3 else 1)' >/dev/null 2>&1; then PY="$c"; break; fi
done
[[ -n "$PY" ]] || die "결과 XML 을 읽을 python3 가 없다"

xml="$MP/testkit/build/test-results/desktopTest/TEST-com.yehsung.aingcheck.testkit.seal.NetworkCanaryTest.xml"
rm -f "$xml"   # 앞 실행(봉인 게이트)의 초록 결과를 대조 결과로 잘못 읽지 않게

cd "$MP"
AINGCHECK_NETWORK_SEALED=1 ./gradlew --offline --no-daemon :testkit:desktopTest --tests '*NetworkCanaryTest*'
rc=$?

verdict="$("$PY" -I - "$xml" "$rc" <<'PY'
import re, sys, xml.etree.ElementTree as ET
path, rc = sys.argv[1], int(sys.argv[2])
why = []
if rc == 0:
    why.append("gradle-exit=0(봉인 없이도 초록 — 카나리아가 아무것도 재지 않는다)")
try:
    root = ET.parse(path).getroot()
except Exception as e:
    print(f"bad rc={rc} 결과 XML 없음({type(e).__name__}) — 시험이 돌지 않았다(컴파일·의존·필터 실패)")
    sys.exit(0)
suites = [root] if root.tag == "testsuite" else list(root.iter("testsuite"))
tests = sum(int(s.get("tests", 0)) for s in suites)
skipped = sum(int(s.get("skipped", 0)) for s in suites)
failures = [f for s in suites for f in s.iter("failure")]
errors = [e for s in suites for e in s.iter("error")]
out = "\n".join((s.findtext("system-out") or "") for s in suites)
if tests < 1 or skipped:
    why.append(f"tests={tests} skipped={skipped}(카나리아가 돌지 않았다)")
if errors:
    why.append(f"errors={len(errors)}(단언 실패가 아닌 예외)")
if not any("봉인이 새고 있다" in (f.get("message") or "") + (f.text or "") for f in failures):
    why.append(f"failures={len(failures)} 중 '봉인이 새고 있다' 단언 실패가 없다")
canary = [l.strip() for l in out.splitlines() if "AINGCHECK-CANARY" in l]
if not any(re.search(r"AINGCHECK-CANARY .*OPEN", l) for l in canary):
    why.append("AINGCHECK-CANARY … OPEN 줄이 없다(바깥 연결이 열린 증거 없음)")
head = "ok" if not why else "bad"
print(f"{head} rc={rc} tests={tests} failures={len(failures)} errors={len(errors)} canary={canary[:1]} {'; '.join(why)}")
PY
)"
echo "canary-contrast: $verdict"
[[ "${verdict%% *}" == "ok" ]] || { echo "canary-contrast: 대조 실패 — 봉인 없는 빨강이 '봉인이 새었다'로 증명되지 않았다" >&2; exit 1; }
echo "canary-contrast: 봉인 없는 카나리아가 '봉인이 새었다'로 빨강 — 예상대로"
