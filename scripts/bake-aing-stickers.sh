#!/bin/zsh
# 아잉이 이모티콘 여섯 장을 굽는다 (v0.3.63 — 이미지 모델 판).
#
# 0.3.62 까지는 3D 렌더 위에 눈·입을 Core Graphics 로 **덧칠**했다. 사용자가 거부했다 —
# 덧칠 자국 네모가 보이고 눈이 원본의 반질반질한 입체 눈이 아니었다(2026-10-22).
# 지금은 **Codex CLI 의 내장 이미지 생성 도구**로 굽는다.
#
# ⚠️ **같은 입력이어도 결과가 매번 다르다.** 옛 스크립트는 바이트까지 같았지만 이미지 모델은 아니다.
#    그래서 이 스크립트는 '재현'이 아니라 '만드는 방법'을 적어 둔 것이다 — 다시 구우면 **눈으로 보고**
#    마음에 드는 장만 남겨라(한 장씩 다시 굽는 법은 아래 사용법).
#
# 파이프라인 세 칸:
#   ① scripts/render-aing-reference.swift — 앱과 같은 구도로 아잉이를 1024 로 렌더해 **바짝 잘라** 둔다.
#      이걸 모델에 같이 넣는 것이 핵심이다. 안 넣으면 "닮았는데 다른 애"가 나온다.
#   ② codex exec — 아래 프롬프트. **"새로 디자인하지 마라, 얼굴 표정만 바꿔라"** 가 전부다.
#      장식은 머리보다 훨씬 작은 것 최대 두 개로 묶는다(사용자 지시: "너무 과해").
#   ③ scripts/fit-sticker.swift — 알파 잡티를 걷고 **몸통 기준**으로 512 에 맞춘다.
#
# 사용법:
#   scripts/bake-aing-stickers.sh                 # 없는 것만 굽는다
#   scripts/bake-aing-stickers.sh joy sad         # 그 장만 다시 굽는다(기존 파일을 덮는다)
#
# 함정: 동시에 여러 장을 던지면 **429 Too Many Requests** 로 창이 통째로 막힌다(실측).
#       반드시 한 장씩, 사이를 두고 돈다.
set -u
cd "$(dirname "$0")/.."
REPO="$PWD"
STICKERS="$REPO/Sources/CheckCore/Resources/Stickers"
WORK="${TMPDIR:-/tmp}/aing-sticker-bake"
REF="$WORK/aing-ref.png"
GAP=50            # 장 사이 쉬는 시간(초) — 429 를 피하는 유일한 수단이다

typeset -A EXPR
EXPR[joy]="Expression: a happy smile — the eyes become gentle upward crescent arcs and the mouth is a small open smile. One or two tiny sparkles nearby."
EXPR[heart]="Expression: in love — the eyes become small soft pink hearts and the mouth is a tiny closed happy smile. One or two small pink hearts float nearby."
EXPR[sad]="Expression: sad — the eyes look down and are a little watery, the eyebrows slant up in the middle, and the mouth is a small downturned curve. One small teardrop at the corner of one eye."
EXPR[angry]="Expression: annoyed — the eyebrows slant down and inward, the eyes narrow a little, and the mouth is a small pout. One small red cross-shaped anger mark near the top of the head."
EXPR[sleepy]="Expression: sleepy — the eyes are closed as gentle downward curves and the mouth is a small sleepy oval as if yawning. Two or three tiny 'z' letters drift up to one side."
EXPR[surprised]="Expression: surprised — the eyes are wide and round with a bright highlight, and the mouth is a small round open 'o'. One small exclamation mark near the head."
ORDER=(joy heart sad angry sleepy surprised)

mkdir -p "$WORK" "$STICKERS"
if [[ ! -f "$REF" ]]; then
  echo "레퍼런스를 굽는다…"
  swift "$REPO/scripts/render-aing-reference.swift" "$REPO/Sources/check/Resources/aing.scn" "$REF" 1024 || exit 1
fi

if (( $# > 0 )); then
  TARGETS=("$@")
else
  TARGETS=()
  for id in $ORDER; do [[ -f "$STICKERS/sticker-$id.png" ]] || TARGETS+=$id; done
fi
(( ${#TARGETS} == 0 )) && { echo "여섯 장이 이미 다 있다. 다시 구우려면 아이디를 인자로 줘라."; exit 0; }

for id in $TARGETS; do
  [[ -n "${EXPR[$id]:-}" ]] || { echo "모르는 아이디: $id"; exit 2; }
  echo "=== $id ==="
  PROMPT="내장 이미지 생성 도구(image_gen)로 그림 한 장을 만들어 이 폴더에 저장해라. 다른 일은 하지 마라.
입력 그림을 최대한 그대로 살리는 쪽(input fidelity high)으로 요청하고, 배경은 실제로 투명하게(알파 유지) 받아라.

- 입력/참고 그림: ./aing-ref.png — 이 캐릭터가 '아잉이'다. **새로 디자인하지 마라. 이 캐릭터를 그대로 다시 그려라.**
- 저장 파일명: ./sticker-${id}.png
- 1024x1024, 배경 완전 투명, PNG

프롬프트로 쓸 내용:
Redraw the EXACT character from the reference image. This is the same mascot, not a new design.
Keep identical: the rounded teardrop body silhouette and its proportions, the two small rounded nub
ears low on the left and right sides, the smooth glossy soft-3D clay finish, the vertical gradient
from pale lavender at the top to periwinkle violet at the bottom, the large glossy dark-brown oval
eyes with a single bright white highlight, and the small soft pink oval blush on each cheek.
Change ONLY the facial expression. Do not change the body, the colors, the ear shape or the finish.
${EXPR[$id]}
Keep decoration minimal and restrained: at most two small simple accent marks, each much smaller
than the head and placed just outside the body. No confetti, no large props, no busy effects.
The character fills most of the frame, centered, full body, on a fully transparent background.
No outline, no border, no ground shadow, no background, no text, no watermark.

끝나면 저장한 파일 경로만 한 줄로 알려라."
  rm -f "$WORK/sticker-$id.png"
  ( cd "$WORK" && timeout 900 codex exec --sandbox workspace-write --skip-git-repo-check "$PROMPT" </dev/null ) \
    > "$WORK/log-$id.txt" 2>&1
  if [[ -f "$WORK/sticker-$id.png" ]]; then
    swift "$REPO/scripts/fit-sticker.swift" "$WORK/sticker-$id.png" "$STICKERS/sticker-$id.png" 512 0.62
  else
    echo "  실패: $(tail -1 "$WORK/log-$id.txt")"
  fi
  sleep $GAP
done
echo "끝. 눈으로 확인해라: open $STICKERS"
