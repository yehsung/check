"""이슬 아잉이 카드(HEIC base64) 한 줄만 대체 그림으로 바꾼다 — `MeCharacterCardData-alt.patch` 가 안 먹을 때(카드 파일이 그사이 다시 구워졌을 때)의 예비 길.

사용(저장소 루트에서):
    python3 -I <이 파일> Sources/CheckMobileKit/Me/MeCharacterCardData.swift <isul-alt>/card-aing_isul.heic.base64.txt

`id: "aing_isul"` 카드의 `heicBase64: "…"` 값만 바꾸고 다른 카드 · 머리말은 한 글자도 안 건드린다. 이슬 카드가 없거나 두 번 나오면 멈춘다.
파일을 지우거나 새로 만들지 않는다(같은 파일을 덮어쓴다).
"""
import re
import sys

target, replacement_file = sys.argv[1], sys.argv[2]
text = open(target, encoding="utf-8").read()
new_b64 = open(replacement_file, encoding="utf-8").read().strip()
if not re.fullmatch(r"[A-Za-z0-9+/=]+", new_b64):
    sys.exit("base64 파일 모양이 아니다")
if text.count('id: "aing_isul"') != 1:
    sys.exit("이슬 카드가 정확히 하나가 아니다 — 손으로 확인하라")
start = text.index('id: "aing_isul"')
match = re.compile(r'heicBase64: "([^"]+)"').search(text, start)
if match is None:
    sys.exit("이슬 카드의 heicBase64 를 못 찾았다")
if match.group(1) == new_b64:
    sys.exit("이미 대체 그림이다 — 바꿀 것 없음")
text = text[: match.start(1)] + new_b64 + text[match.end(1):]
open(target, "w", encoding="utf-8").write(text)
print("이슬 카드 HEIC 를 대체 그림으로 바꿨다:", target)
