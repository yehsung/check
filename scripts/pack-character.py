"""스프라이트 캐릭터 에셋 팩커 — 원본 PNG 더미를 앱이 읽는 아틀라스 + 매니페스트로 굽는다.

인터프리터
----------
shebang 을 일부러 두지 않았다(개발 맥마다 `python3` 가 시스템/anaconda/venv 로 갈린다).
**Pillow + NumPy 가 있는 아무 인터프리터**로 돌리면 된다.

    python3 scripts/pack-character.py --id fox ...

Pillow 가 없으면(`ModuleNotFoundError: PIL`) Pillow·NumPy 가 깔린 venv 를 직접 지목한다:

    <scratchpad>/sprite-gen/.venv/bin/python scripts/pack-character.py --id fox ...

사용법
------
    python3 scripts/pack-character.py \
        --id fox --name 여우 \
        --src <scratchpad>/charexp/app-candidates \
        --walk-order 0,1,2,1 \
        --out Sources/check/Characters/fox

`--src` 만 주면 픽스처 관용구로 입력을 찾는다(개별 `--neutral/--negative/--walk-dir` 로 덮어쓸 수 있다):
  <src>/<id>-neutral-PAIRTIGHT.png · <src>/<id>-negative-PAIRTIGHT.png
  <src>/<id>-walk-right/frame-N.png  (없으면 <src>/walk-right/frame-N.png)

산출물
------
    <out>/manifest.json          갈래 1 `CharacterManifest` 가 그대로 디코드하는 스키마
    <out>/atlas.png              프레임 셀을 가로 한 줄로 이어붙인 아틀라스
    <out>/portrait-neutral.png   192² 메뉴바·팝오버용(입력을 그대로 재인코딩)
    <out>/portrait-negative.png  192²

설계에서 중요한 두 가지 — 둘 다 실측으로 데인 자리다
----------------------------------------------------
1. **등록(registration)은 그룹 공유 변환이다.** 한 상태 그룹(정면 표정 쌍 / 옆모습 걷기)의 프레임들을
   각자 tight-crop 하면 재생 중 캐릭터가 튄다(슬픈 여우가 귀 때문에 bbox 가 27px 낮아 혼자 더 확대됐다).
   그래서 **그룹 union bbox 로 한 번만 크롭**하고 **그룹당 스케일 하나**만 쓴다.
2. **모든 셀은 같은 크기다.** 런타임(`SpriteCharacterNode`)은 평면 크기를 `frontIdle` 첫 프레임 rect
   하나로만 정하고 그 뒤로는 `contentsTransform`(UV)만 바꾼다 — 상태마다 rect 종횡비가 다르면
   옆모습이 정면 평면에 늘어붙는다. 그래서 그룹 간에도 **내용 높이를 맞춘 뒤 공통 셀**에 앉힌다.

그리고 결정론: 같은 입력이면 같은 바이트다(메타데이터·타임스탬프를 쓰지 않는다). 재실행이 diff 를 만들면 안 된다.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from typing import List, Sequence, Tuple

try:
    import numpy as np
    from PIL import Image
except ModuleNotFoundError as exc:  # 어느 인터프리터로 돌렸는지까지 알려줘야 헤매지 않는다.
    sys.stderr.write(
        "error: {} 이(가) 없다 (interpreter={}).\n".format(exc.name, sys.executable)
        + "       Pillow·NumPy 가 깔린 인터프리터로 다시 돌려라 — 파일 상단 주석 참고.\n"
    )
    raise SystemExit(2)


# 알파가 이 값보다 크면 '내용'. 1 = 완전 투명만 여백으로 본다(보수적 — 소프트 엣지를 자르지 않는다).
# ── 캐릭터별 초상 크롭 조정 ─────────────────────────────────────────────────────────────────
# **왜 캐릭터마다 다른가**(2026-09-13 실측): 같은 규칙으로 잘라도 실루엣 비율이 다르면 18pt 에서
# 읽히는 정도가 갈린다. 픽셀아트 5종 측정 — 36px 점유율 시바 66.6 · 판다 69.2 · 드래곤 60.9 ·
# 슬라임 59.3 인데 **토끼만 49.2**(귀가 세로를 다 먹는다). 대비도 30.4 로 꼴찌(아잉 43.0 보다 낮다).
#
# 종이 다섯뿐이므로 규칙 하나를 억지로 찾는 대신 **그 종만 조정한다**. 여기 없는 캐릭터는 기본값.
#   head_side : 머리 상자 한 변(몸통 높이 대비). 키우면 더 넓게(몸까지), 줄이면 얼굴만.
#   head_top  : 얼굴 중심을 찾을 위쪽 띠 비율. 귀·뿔이 큰 종은 줄여야 중심이 위로 안 끌린다.
# ⚠️ **다리 띠 미러(--contact-b-from)는 픽셀아트 전용이다.** 글로시 3D 화풍에서는 쓰지 마라 —
#    그라디언트가 연속이라 가로 절단선이 그대로 보인다(2026-09-13 실측, bandsweep 5단계: band 0.16
#    이상은 전부 몸통에 이음매가 생기고, 0.12 는 이음매는 없지만 발만 뒤집혀 다리 교대가 안 된다).
#    픽셀아트에서 통했던 이유는 블록 경계가 이미 계단이라 절단선이 묻혔기 때문이다.
#    글로시는 **접지 B 를 새로 생성한다** — 접지 A 를 ref 로 붙여 "편집"시키지 말고 베이스(정면)만
#    주고 대각 반대쪽을 처음부터 그리게 하면 된다. 픽셀아트 라운드가 실패한 건 낱말이 아니라 그
#    "편집" 경로 때문이었다(코덱스는 첨부 그림을 보존하는 쪽으로 강하게 치우친다).
#    실측 다리띠 IoU(낮을수록 다리가 바뀐 것): 시바 0.702 · 다람쥐 0.754 · 여우 0.507
#    — 픽셀아트 라운드의 편집 방식은 0.86~0.95 였다(= 거의 안 움직임).
WALK_TUNING = {
    # leg_band: 아래에서부터 몇 %를 "다리"로 보고 미러할지. 꼬리가 낮으면 좁혀라.
    # 지금 번들에는 이 표를 쓰는 캐릭터가 없다(5종 전부 글로시 = 접지 B 를 생성한다). 픽셀아트
    # 캐릭터를 다시 넣을 때를 위해 기구는 남겨 둔다.
}

PORTRAIT_TUNING = {
    # "rabbit": {"head_side": 0.52, "head_top": 0.60},   # 리롤 후 재측정해서 필요하면 켠다
}
# ───────────────────────────────────────────────────────────────────────────────────────────

PORTRAIT_SIZE = 192   # 메뉴바(18pt)·팝오버(46pt)가 함께 쓰는 초상 한 변
# 아틀라스 셀 **높이 상한**. 입력 원본이 커도 여기서 잘린다.
#
# **왜 상한이 필요한가**: 픽셀아트 입력은 원래 작아서(셀 236px) 상한이 없어도 됐다. 글로시 3D 입력은
# 한 변이 1200~1400px 라 그대로 구우면 셀 1200px × 4장 = 아틀라스 5000px 급이 된다 — 번들에 못 넣는다.
#
# **왜 하필 이 숫자인가**(2026-09-13 실측):
#   · 평상시 데스크톱 패널은 `CheckOverlayWindow.panelSize` = 140×170pt → 1배 170px · 2배 340px.
#   · 최대 확대 지점은 **울트라 찌르기 5초 격발**이다. `ultraPanelFrame(in:) = screenFrame` 이라
#     화면 전체로 커진다. 개발 맥 주 모니터는 1920×1080 @1배 → 세로 1080px.
#     (2배 레티나 1440p 사용자라면 ~2880px 까지 갈 수 있다.)
#   · 즉 평상시는 512 로 **충분히 남고**(패널 170px 기준 3.4배 과표본), 격발 5초 동안만 2.1배
#     업스케일이 된다. 글로시는 원래 부드러운 그라디언트라 업스케일이 픽셀아트만큼 티나지 않는다.
#   · 번들 무게 실측(글로시 5종 아틀라스 PNG 합계):
#         상한 384 → 2.9MB (셀 426×388)   상한 512 → 5.0MB (셀 567×516)   상한 768 → 9.3MB (셀 805×732)
#     앱 전체가 32MB, 리소스 번들이 9.3MB 다. 512 는 +5.0MB 로 값을 치를 만하고 768 은 격발 5초를
#     위해 4.3MB 를 더 내는 셈이라 접었다. 384 는 격발에서 2.8배 확대라 조금 무르다.
#   · 메뉴바·팝오버 초상은 이 아틀라스가 아니라 `portrait-*.png`(192², 5종 합계 0.57MB)를 쓰므로
#     여기 계산과 무관하다.
DEFAULT_MAX_CELL_HEIGHT = 512
DEFAULT_ALPHA_THRESHOLD = 1
# 셀 사방에 두는 투명 여백(px). diffuse 가 clamp + linear 라 셀 경계에서 이웃 셀이 번질 수 있는데,
# 번져 들어오는 쪽이 투명이면 결과도 투명이다.
GUTTER = 2

Rect = Tuple[int, int, int, int]  # (x0, y0, x1, y1) — 우/하 배타


# MARK: - 이미지 유틸

def load_rgba(path: str) -> "np.ndarray":
    """PNG 를 RGBA uint8 배열로 읽는다."""
    with Image.open(path) as im:
        return np.array(im.convert("RGBA"))


def alpha_bbox(image: "np.ndarray", threshold: int) -> Rect:
    """알파 > threshold 인 픽셀의 bbox. 전부 투명이면 이미지 전체를 돌려준다."""
    ys, xs = np.nonzero(image[:, :, 3] > threshold)
    if xs.size == 0:
        return (0, 0, image.shape[1], image.shape[0])
    return (int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1)


def union_bbox(images: Sequence["np.ndarray"], threshold: int) -> Rect:
    """그룹 전체를 덮는 bbox — 이게 '공유 변환'의 크롭 성분이다."""
    boxes = [alpha_bbox(img, threshold) for img in images]
    return (
        min(b[0] for b in boxes),
        min(b[1] for b in boxes),
        max(b[2] for b in boxes),
        max(b[3] for b in boxes),
    )


def crop(image: "np.ndarray", box: Rect) -> "np.ndarray":
    x0, y0, x1, y1 = box
    return image[y0:y1, x0:x1]


def resize_rgba(image: "np.ndarray", size: Tuple[int, int], nearest: bool = False) -> "np.ndarray":
    """알파를 곱해 두고 줄인다(premultiplied).

    투명 픽셀의 RGB 가 0(검정)이라 그냥 리샘플하면 가장자리가 검게 번진다 — 실제로 입력이 그렇다.
    """
    width, height = size
    if (image.shape[1], image.shape[0]) == (width, height):
        return image

    src = image.astype(np.float64)
    alpha = src[:, :, 3:4] / 255.0
    premultiplied = np.concatenate([src[:, :, :3] * alpha, src[:, :, 3:4]], axis=2)
    packed = np.clip(np.rint(premultiplied), 0, 255).astype(np.uint8)

    with Image.fromarray(packed, "RGBA") as im:
        # 픽셀아트는 **NEAREST** 여야 한다 — LANCZOS 는 격자를 뭉개 픽셀아트의 유일한 특징을 지운다.
        # 앱 쪽 재질 필터(.nearest)와 **짝이다**: 둘 중 하나만 해도 소용없다.
        resample = Image.NEAREST if nearest else Image.LANCZOS
        resized = np.array(im.resize((width, height), resample)).astype(np.float64)

    out_alpha = resized[:, :, 3:4] / 255.0
    rgb = np.where(out_alpha > 0, resized[:, :, :3] / np.maximum(out_alpha, 1e-6), 0.0)
    out = np.concatenate([rgb, resized[:, :, 3:4]], axis=2)
    return np.clip(np.rint(out), 0, 255).astype(np.uint8)


def save_png(image: "np.ndarray", path: str) -> None:
    """결정론적 PNG 쓰기 — info 가 빈 새 이미지라 tIME·텍스트 청크가 붙지 않는다."""
    with Image.fromarray(image, "RGBA") as im:
        im.save(path, format="PNG", optimize=False, compress_level=9)


# MARK: - 등록(registration)

class Group:
    """하나의 공유 변환으로 앉히는 프레임 묶음."""

    def __init__(self, name: str, frames: List["np.ndarray"], threshold: int, nearest: bool = False):
        self.name = name
        self.nearest = nearest
        self.box = union_bbox(frames, threshold)
        # 크롭까지가 '공유'다 — 여기서 프레임별로 다르게 굴면 재생 중에 튄다.
        self.crops = [crop(f, self.box) for f in frames]
        self.width = self.box[2] - self.box[0]
        self.height = self.box[3] - self.box[1]

    def scaled(self, target_height: int) -> List["np.ndarray"]:
        """그룹 전체에 **같은** 스케일을 먹인다."""
        width = max(1, int(round(self.width * target_height / self.height)))
        return [resize_rgba(c, (width, target_height), nearest=self.nearest) for c in self.crops]


# ── 접지 B 를 다리 띠 미러로 만든다 ─────────────────────────────────────────────────────────
# **왜 이렇게 하는가**(2026-09-13 실측): 옆모습 걷기의 두 접지는 **다리만 좌우가 바뀐 같은 그림**이다.
# 그런데 이미지 모델은 그 반전을 못 한다 — 픽셀아트 5종에 깊이 언어·위치 언어·4족·2족 전부 시도했고
# **한 종도** 다리를 교대시키지 못했다(다리띠 IoU 0.86~0.95 = 거의 안 움직임). 원인은 낱말이 아니라
# 편집 경로 자체다: 코덱스는 첨부한 승인 그림을 **보존하는 쪽으로 강하게 치우친다.**
#
# 그래서 생성 대신 픽셀로 뒤집는다. 결정적이고, 콜을 안 쓰고, 원본에서 한 톨도 안 벗어난다.
# 덤: 근/원 다리의 **명암 차이까지 같이 뒤집힌다**(시바는 앞다리가 크림·뒷다리가 어두운데, 그게 곧
# near/far 음영이다) — 모델에게 시키려던 바로 그 일이 공짜로 된다.
# 실측 다리띠 IoU (낮을수록 많이 바뀐 것): 시바 0.921→0.765 · 판다 0.945→0.801 ·
#                                          토끼 0.860→0.756 · 드래곤 0.895→0.631
#
# ⚠️ 띠 높이는 **종마다 다르다**(WALK_TUNING). 꼬리가 낮게 달린 종은 좁혀야 꼬리가 같이 뒤집히지 않는다.
def mirror_leg_band(image: "np.ndarray", band_frac: float, threshold: int) -> "np.ndarray":
    x0, y0, x1, y1 = alpha_bbox(image, threshold)
    cut = y1 - int((y1 - y0) * band_frac)
    band = image[cut:y1].copy()
    alpha = band[:, :, 3].astype("float64")
    columns = np.arange(band.shape[1], dtype="float64")[None, :]
    # 축은 **다리 띠의 알파 무게중심**이다. 이미지 중앙으로 뒤집으면 다리가 몸 밖으로 나간다.
    center = float((columns * alpha).sum() / max(alpha.sum(), 1.0))
    shift = int(round(2 * center - (band.shape[1] - 1)))
    out = image.copy()
    out[cut:y1] = np.roll(band[:, ::-1], shift, axis=1)
    return out


def head_box(image: "np.ndarray", threshold: int, top_frac: float, side_frac: float) -> Rect:
    """얼굴만 잘라낼 정사각 상자를 추정한다.

    ⚠️ **지금 번들 5종은 이 경로를 안 쓴다**(`--head-side 0` = 전신 초상). 사용자가 2026-09-13 오후에
       "메뉴바·헤더도 전신이 다 들어가게"로 뒤집었다. 아래 근거는 여전히 사실이므로 기구는 남긴다 —
       표정 구분이 중요한 캐릭터가 생기면 `--head-side` 를 다시 주면 된다.

    **왜 필요한가**(2026-09-13 실측): 전신 스프라이트를 그대로 메뉴바 18pt(36px)에 넣으면 얼굴이 몇
    픽셀로 줄어 "주황색 덩어리 / 흰 덩어리"가 된다 — 근무/비근무 표정 구분이 통째로 사라진다. 아잉은
    캐릭터 자체가 두상이라 이 문제가 없었고, 그래서 전신 캐릭터를 처음 넣은 지금에야 드러났다.

    추정: 몸통 위쪽 `top_frac` 띠 안의 **어두운 픽셀**(눈·코) 무게중심을 얼굴 중심 x 로 본다.
    어두운 픽셀이 없으면 그 띠의 알파 무게중심으로 폴백한다. 세로는 몸통 맨 위에서 시작한다.
    """
    x0, y0, x1, y1 = alpha_bbox(image, threshold)
    height = y1 - y0
    band_bottom = y0 + max(1, int(height * top_frac))
    band = image[y0:band_bottom, x0:x1].astype("float32")
    band_alpha = band[..., 3]
    luma = 0.299 * band[..., 0] + 0.587 * band[..., 1] + 0.114 * band[..., 2]
    dark = (band_alpha > 64) & (luma < 90)
    if int(dark.sum()) >= 20:
        center_x = x0 + float(np.nonzero(dark)[1].mean())
    else:
        columns = np.arange(band.shape[1], dtype="float32")[None, :]
        weight = max(float(band_alpha.sum()), 1.0)
        center_x = x0 + float((columns * band_alpha).sum() / weight)
    side = max(8, int(height * side_frac))
    left = int(round(center_x - side / 2.0))
    return (left, y0, left + side, y0 + side)


def pair_locked_head_box(images: Sequence["np.ndarray"], threshold: int,
                         top_frac: float, side_frac: float) -> Rect:
    """표정 쌍이 **같은 상자**를 쓰게 union 을 잡고 정사각으로 맞춘다.

    따로 잡으면 상자가 달라져(실측: 여우 neutral y=13 side=102 vs negative y=37 side=88)
    표정이 바뀔 때 메뉴바 아이콘이 튄다. 이 저장소가 리센터링에서 이미 겪은 함정과 같다.
    """
    boxes = [head_box(image, threshold, top_frac, side_frac) for image in images]
    left = min(b[0] for b in boxes); top = min(b[1] for b in boxes)
    right = max(b[2] for b in boxes); bottom = max(b[3] for b in boxes)
    side = max(right - left, bottom - top)
    cx = (left + right) // 2
    cy = (top + bottom) // 2
    return (cx - side // 2, cy - side // 2, cx - side // 2 + side, cy - side // 2 + side)


def crop_padded(image: "np.ndarray", box: Rect) -> "np.ndarray":
    """상자가 이미지 밖으로 나가도 투명으로 메워 잘라낸다(머리가 위쪽 가장자리에 붙어 있을 때)."""
    x0, y0, x1, y1 = box
    out = np.zeros((y1 - y0, x1 - x0, 4), dtype=image.dtype)
    sx0, sy0 = max(0, x0), max(0, y0)
    sx1, sy1 = min(image.shape[1], x1), min(image.shape[0], y1)
    if sx1 > sx0 and sy1 > sy0:
        out[sy0 - y0:sy1 - y0, sx0 - x0:sx1 - x0] = image[sy0:sy1, sx0:sx1]
    return out


def fit_square(image: "np.ndarray", size: int, nearest: bool = False) -> "np.ndarray":
    """비율을 유지한 채 `size`² 투명 캔버스 한가운데에 앉힌다(잘라내지 않는다).

    초상은 메뉴바(18pt)와 팝오버 헤더(46pt)가 **같은 PNG 한 장**을 쓰고 둘 다 `scaledToFit` 이므로,
    여백까지 포함해 정사각으로 구워 두면 두 곳의 크기 계산이 서로 어긋날 일이 없다.
    """
    height, width = image.shape[:2]
    scale = min(size / max(width, 1), size / max(height, 1))
    new_w = max(1, int(round(width * scale)))
    new_h = max(1, int(round(height * scale)))
    resized = resize_rgba(image, (new_w, new_h), nearest=nearest)
    out = np.zeros((size, size, 4), dtype=np.uint8)
    x = (size - new_w) // 2
    y = (size - new_h) // 2
    out[y:y + new_h, x:x + new_w] = resized
    return out


def place(content: "np.ndarray", cell_w: int, cell_h: int) -> "np.ndarray":
    """셀 안에 가로 중앙·세로 바닥 정렬로 앉힌다(발이 같은 접지선에 있어야 상태 전환에 안 뛴다)."""
    cell = np.zeros((cell_h, cell_w, 4), dtype=np.uint8)
    x = (cell_w - content.shape[1]) // 2
    y = cell_h - GUTTER - content.shape[0]
    cell[y:y + content.shape[0], x:x + content.shape[1]] = content
    return cell


# MARK: - 입력 해석

def resolve_inputs(args: argparse.Namespace) -> Tuple[str, str, str]:
    """--src 관용구 + 개별 덮어쓰기."""
    neutral = args.neutral
    negative = args.negative
    walk_dir = args.walk_dir

    if args.src:
        neutral = neutral or os.path.join(args.src, args.id + "-neutral-PAIRTIGHT.png")
        negative = negative or os.path.join(args.src, args.id + "-negative-PAIRTIGHT.png")
        if walk_dir is None:
            # 여우는 fox-walk-right/, 로봇은 walk-right/ 다(픽스처가 그렇게 생겼다).
            candidates = [
                os.path.join(args.src, args.id + "-walk-right"),
                os.path.join(args.src, "walk-right"),
            ]
            walk_dir = next((c for c in candidates if os.path.isdir(c)), None)

    missing = [
        name for name, path in (("--neutral", neutral), ("--negative", negative), ("--walk-dir", walk_dir))
        if not path
    ]
    if missing:
        raise SystemExit("error: 입력을 찾지 못했다: " + ", ".join(missing))
    for path in (neutral, negative):
        if not os.path.isfile(path):
            raise SystemExit("error: 파일이 없다: " + path)
    if not os.path.isdir(walk_dir):
        raise SystemExit("error: 디렉터리가 없다: " + walk_dir)
    return neutral, negative, walk_dir


def walk_frame_paths(walk_dir: str) -> List[str]:
    """frame-0.png, frame-1.png … 를 번호순으로. 정렬이 흔들리면 재생 순서가 흔들린다."""
    names = [n for n in os.listdir(walk_dir) if n.startswith("frame-") and n.endswith(".png")]
    if not names:
        raise SystemExit("error: " + walk_dir + " 에 frame-N.png 가 없다")
    names.sort(key=lambda n: int(n[len("frame-"):-len(".png")]))
    return [os.path.join(walk_dir, n) for n in names]


def parse_order(text: str, frame_count: int) -> List[int]:
    order = [int(t) for t in text.split(",") if t.strip() != ""]
    if not order:
        raise SystemExit("error: --walk-order 가 비었다")
    for index in order:
        if not 0 <= index < frame_count:
            raise SystemExit(
                "error: --walk-order 의 {} 가 프레임 범위(0..{}) 밖이다".format(index, frame_count - 1)
            )
    return order


# MARK: - 본체

def pack(args: argparse.Namespace) -> None:
    neutral_path, negative_path, walk_dir = resolve_inputs(args)
    walk_paths = walk_frame_paths(walk_dir)

    order = parse_order(args.walk_order, len(walk_paths)) if args.walk_order else list(range(len(walk_paths)))
    side_idle = args.side_idle if args.side_idle is not None else order[min(1, len(order) - 1)]
    if not 0 <= side_idle < len(walk_paths):
        raise SystemExit("error: --side-idle {} 가 프레임 범위 밖이다".format(side_idle))

    # 아틀라스에 굽는 원본 프레임 = 실제로 쓰이는 것만(여우는 0,1,2,1 이라 f3 이 통째로 빠진다).
    used = sorted(set(order) | {side_idle})

    neutral = load_rgba(neutral_path)
    negative = load_rgba(negative_path)
    walk_frames = [load_rgba(walk_paths[i]) for i in used]

    # 접지 B 를 **다리 띠 미러**로 만든다(mirror_leg_band 주석에 근거). `--contact-b-from N` 이 원본
    # 프레임 N(보통 접지 A = 0)을 지목하고, `--contact-b-slot M` 이 그 결과가 앉을 프레임 번호다.
    # 모델이 만든 M 번 프레임은 **버린다** — 다리를 안 바꾸므로 총총거림이 된다.
    if args.contact_b_from is not None:
        band = WALK_TUNING.get(args.id, {}).get("leg_band", args.leg_band)
        slot = args.contact_b_slot if args.contact_b_slot is not None else max(used)
        if args.contact_b_from not in used or slot not in used:
            raise SystemExit("error: --contact-b-from/slot 이 실제로 쓰이는 프레임이 아니다")
        source = walk_frames[used.index(args.contact_b_from)]
        walk_frames[used.index(slot)] = mirror_leg_band(source, band, args.alpha_threshold)
        print("[{}]   접지B = 프레임 {} 의 다리 띠 미러(band={}) → 프레임 {}".format(
            args.id, args.contact_b_from, band, slot))

    # 정면 표정 쌍은 이미 pair-lock 된 입력이지만, 아틀라스 셀로 앉힐 때도 **쌍의 공유 변환**이어야 한다.
    front = Group("front", [neutral, negative], args.alpha_threshold, nearest=args.pixel_art)
    side = Group("side", walk_frames, args.alpha_threshold, nearest=args.pixel_art)

    # 그룹 간에도 **키(높이)를 맞춘다** — 정면/옆모습에서 캐릭터가 커졌다 작아지면 안 된다.
    # 확대는 하지 않는다(작은 쪽에 맞춘다): 업스케일은 흐려질 뿐 정보가 늘지 않는다.
    target_height = min(front.height, side.height)
    # 그 위에 **상한을 한 겹 더** 씌운다(--max-height). 축소만 하므로 위 규칙과 충돌하지 않는다.
    # 왜 필요한가 · 숫자 근거는 DEFAULT_MAX_CELL_HEIGHT 주석에.
    if args.max_height > 0:
        target_height = min(target_height, args.max_height)
    front_cells = front.scaled(target_height)
    side_cells = side.scaled(target_height)

    content_w = max(cell.shape[1] for cell in front_cells + side_cells)
    cell_w = content_w + 2 * GUTTER
    cell_h = target_height + 2 * GUTTER

    # 셀 순서: [0] = frontIdle(neutral), [1...] = 쓰이는 걷기 프레임(원본 인덱스 오름차순).
    cells = [place(front_cells[0], cell_w, cell_h)] + [place(c, cell_w, cell_h) for c in side_cells]
    atlas = np.zeros((cell_h, cell_w * len(cells), 4), dtype=np.uint8)
    for i, cell in enumerate(cells):
        atlas[:, i * cell_w:(i + 1) * cell_w] = cell

    def rect(cell_index: int) -> dict:
        return {"x": cell_index * cell_w, "y": 0, "w": cell_w, "h": cell_h}

    cell_of = {src_index: 1 + slot for slot, src_index in enumerate(used)}

    manifest = {
        "id": args.id,
        "displayName": args.name or args.id,
        "kind": "sprite",
        "atlas": {
            "file": "atlas.png",
            "width": int(atlas.shape[1]),
            "height": int(atlas.shape[0]),
            "states": {
                "frontIdle": {
                    "frames": [rect(0)],
                    "durationsMs": [args.idle_ms],
                    "loop": True,
                },
                "sideIdle": {
                    "frames": [rect(cell_of[side_idle])],
                    "durationsMs": [args.idle_ms],
                    "loop": True,
                },
                "sideWalk": {
                    "frames": [rect(cell_of[i]) for i in order],
                    "durationsMs": [args.walk_ms] * len(order),
                    "loop": True,
                },
            },
        },
        "portrait": {
            "neutral": "portrait-neutral.png",
            "negative": "portrait-negative.png",
        },
        # 앱이 이 값을 보고 재질 필터를 .nearest 로 바꾼다(SpriteCharacterNode). 짝이 맞아야 한다.
        "pixelArt": bool(args.pixel_art),
    }

    os.makedirs(args.out, exist_ok=True)
    save_png(atlas, os.path.join(args.out, "atlas.png"))
    # 메뉴바·팝오버 PNG 는 **얼굴만** 잘라 낸다(head_box 주석 참고 — 전신은 18pt 에서 덩어리가 된다).
    # 쌍은 같은 상자를 쓴다. --head-side 0 을 주면 자르지 않고 입력을 그대로 쓴다(아잉처럼 이미 두상인 캐릭터).
    if args.head_side > 0:
        tuning = PORTRAIT_TUNING.get(args.id, {})
        # ⚠️ 이름을 `side` 로 두지 마라 — 위의 옆모습 Group `side` 를 덮어써 맨 아래 요약 print 가
        #    `AttributeError: 'float' object has no attribute 'width'` 로 죽는다(산출물은 이미 다 쓴
        #    뒤라 파일은 멀쩡한데 종료코드만 1 이다 = 스크립트로 감싸면 조용히 실패로 보인다).
        head_side = tuning.get("head_side", args.head_side)
        head_top = tuning.get("head_top", args.head_top)
        if tuning:
            print("[{}]   캐릭터별 조정 적용: head_side={} head_top={}".format(args.id, head_side, head_top))
        box = pair_locked_head_box([neutral, negative], args.alpha_threshold, head_top, head_side)
        portrait_neutral = resize_rgba(crop_padded(neutral, box), (PORTRAIT_SIZE, PORTRAIT_SIZE), nearest=args.pixel_art)
        portrait_negative = resize_rgba(crop_padded(negative, box), (PORTRAIT_SIZE, PORTRAIT_SIZE), nearest=args.pixel_art)
        print("[{}]   머리상자 {} (공유) → 초상 {}²".format(args.id, box, PORTRAIT_SIZE))
    else:
        # **전신 초상**(--head-side 0). 사용자 지시(2026-09-13 오후): 메뉴바와 팝오버 헤더 둘 다
        # 얼굴 크롭 말고 전신이 다 들어가게. 그래서 얼굴 상자를 안 잡고 **쌍의 union bbox** 로
        # 한 번만 잘라(표정이 바뀌어도 아이콘이 안 튄다) 정사각에 비율 그대로 앉힌다.
        # ⚠️ 대가: 18pt(36px) 에서 얼굴이 작아져 근무/비근무 표정 구분이 약해진다. 그 구분이
        #    머리 크롭을 만든 이유였는데(head_box 주석), 사용자가 전신을 보고 그쪽을 택했다.
        pair_box = union_bbox([neutral, negative], args.alpha_threshold)
        portrait_neutral = fit_square(crop(neutral, pair_box), PORTRAIT_SIZE, nearest=args.pixel_art)
        portrait_negative = fit_square(crop(negative, pair_box), PORTRAIT_SIZE, nearest=args.pixel_art)
        print("[{}]   전신 초상 — 쌍 union {} → {}²".format(args.id, pair_box, PORTRAIT_SIZE))
    save_png(portrait_neutral, os.path.join(args.out, "portrait-neutral.png"))
    save_png(portrait_negative, os.path.join(args.out, "portrait-negative.png"))
    with open(os.path.join(args.out, "manifest.json"), "w", encoding="utf-8") as handle:
        json.dump(manifest, handle, ensure_ascii=False, indent=2)
        handle.write("\n")

    print("[{}] atlas {}x{} · 셀 {}x{} · 셀 {}장".format(
        args.id, atlas.shape[1], atlas.shape[0], cell_w, cell_h, len(cells)))
    print("[{}]   front union {}x{} · side union {}x{} → 공통 높이 {}".format(
        args.id, front.width, front.height, side.width, side.height, target_height))
    print("[{}]   sideWalk 순서 {} · sideIdle 원본프레임 {} · 구운 프레임 {}".format(
        args.id, order, side_idle, used))
    print("[{}]   → {}".format(args.id, args.out))


def main(argv: List[str]) -> int:
    parser = argparse.ArgumentParser(
        description="캐릭터 PNG 더미 → 아틀라스 + manifest.json",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("--id", required=True, help="캐릭터 ID ([a-z0-9-]{1,32})")
    parser.add_argument("--name", help="표시 이름(기본: --id)")
    parser.add_argument("--src", help="픽스처 루트 디렉터리")
    parser.add_argument("--neutral", help="정면 neutral PNG(--src 관용구를 덮어쓴다)")
    parser.add_argument("--negative", help="정면 negative PNG")
    parser.add_argument("--walk-dir", help="frame-N.png 이 든 오른쪽 걷기 디렉터리")
    parser.add_argument("--walk-order", help="재생 순서(원본 프레임 인덱스, 예: 0,1,2,1). 기본: 전부 순서대로")
    parser.add_argument("--side-idle", type=int, help="옆모습 idle 로 쓸 원본 프레임 인덱스(기본: 재생 순서의 2번째)")
    parser.add_argument("--walk-ms", type=int, default=140, help="걷기 프레임당 ms (기본 140)")
    parser.add_argument("--idle-ms", type=int, default=1000, help="idle 단일 프레임 ms (기본 1000)")
    parser.add_argument("--contact-b-from", type=int,
                        help="접지 B 를 이 원본 프레임의 다리 띠 미러로 만든다(보통 0 = 접지 A)")
    parser.add_argument("--contact-b-slot", type=int,
                        help="미러 결과가 앉을 프레임 번호(기본: 쓰이는 프레임 중 마지막)")
    parser.add_argument("--leg-band", type=float, default=0.34,
                        help="다리로 볼 아래쪽 비율(WALK_TUNING 에 종별 값이 있으면 그쪽이 이긴다)")
    parser.add_argument("--max-height", type=int, default=DEFAULT_MAX_CELL_HEIGHT,
                        help="아틀라스 셀 내용 높이 상한 px (0 = 무제한). 근거는 DEFAULT_MAX_CELL_HEIGHT 주석")
    parser.add_argument("--pixel-art", action="store_true",
                        help="픽셀아트 캐릭터: 리샘플을 NEAREST 로 하고 manifest 에 pixelArt=true 를 적는다")
    parser.add_argument("--head-side", type=float, default=0.62,
                        help="초상 머리 상자 한 변(몸통 높이 대비). 0 이면 자르지 않고 입력 그대로 (기본 0.62)")
    parser.add_argument("--head-top", type=float, default=0.45,
                        help="얼굴 중심을 찾을 위쪽 띠 비율 (기본 0.45)")
    parser.add_argument("--alpha-threshold", type=int, default=DEFAULT_ALPHA_THRESHOLD,
                        help="이 값보다 큰 알파를 내용으로 본다 (기본 {})".format(DEFAULT_ALPHA_THRESHOLD))
    parser.add_argument("--out", required=True, help="산출 디렉터리(예: Sources/check/Characters/fox)")
    args = parser.parse_args(argv)

    # 왼쪽 걷기는 만들지 않는다 — 런타임이 x 미러로 쓴다(추가 에셋 0).
    pack(args)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
