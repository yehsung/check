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


def resize_rgba(image: "np.ndarray", size: Tuple[int, int]) -> "np.ndarray":
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
        resized = np.array(im.resize((width, height), Image.LANCZOS)).astype(np.float64)

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

    def __init__(self, name: str, frames: List["np.ndarray"], threshold: int):
        self.name = name
        self.box = union_bbox(frames, threshold)
        # 크롭까지가 '공유'다 — 여기서 프레임별로 다르게 굴면 재생 중에 튄다.
        self.crops = [crop(f, self.box) for f in frames]
        self.width = self.box[2] - self.box[0]
        self.height = self.box[3] - self.box[1]

    def scaled(self, target_height: int) -> List["np.ndarray"]:
        """그룹 전체에 **같은** 스케일을 먹인다."""
        width = max(1, int(round(self.width * target_height / self.height)))
        return [resize_rgba(c, (width, target_height)) for c in self.crops]


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

    # 정면 표정 쌍은 이미 pair-lock 된 입력이지만, 아틀라스 셀로 앉힐 때도 **쌍의 공유 변환**이어야 한다.
    front = Group("front", [neutral, negative], args.alpha_threshold)
    side = Group("side", walk_frames, args.alpha_threshold)

    # 그룹 간에도 **키(높이)를 맞춘다** — 정면/옆모습에서 캐릭터가 커졌다 작아지면 안 된다.
    # 확대는 하지 않는다(작은 쪽에 맞춘다): 업스케일은 흐려질 뿐 정보가 늘지 않는다.
    target_height = min(front.height, side.height)
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
    }

    os.makedirs(args.out, exist_ok=True)
    save_png(atlas, os.path.join(args.out, "atlas.png"))
    # 메뉴바·팝오버 PNG 는 입력을 그대로 쓴다 — 이미 pair-lock 된 쌍이고, 18pt/46pt 로 검증된 프레이밍이다.
    save_png(neutral, os.path.join(args.out, "portrait-neutral.png"))
    save_png(negative, os.path.join(args.out, "portrait-negative.png"))
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
    parser.add_argument("--alpha-threshold", type=int, default=DEFAULT_ALPHA_THRESHOLD,
                        help="이 값보다 큰 알파를 내용으로 본다 (기본 {})".format(DEFAULT_ALPHA_THRESHOLD))
    parser.add_argument("--out", required=True, help="산출 디렉터리(예: Sources/check/Characters/fox)")
    args = parser.parse_args(argv)

    # 왼쪽 걷기는 만들지 않는다 — 런타임이 x 미러로 쓴다(추가 에셋 0).
    pack(args)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
