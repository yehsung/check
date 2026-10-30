#!/usr/bin/env python3
"""QR codes -> public/assets/brand/*.svg (PLAN 5.3 row 62 · docs/v3/brief.md section 12).

Reproduce:
    cd /Users/yesung/check/landing && python3 scripts/make-qr.py      # = npm run qr
    (needs python `qrcode` >= 7.4 — checked with qrcode 8.2 on /opt/anaconda3/bin/python3)

Outputs (TARGETS):
    qr-appstore.svg       https://apps.apple.com/app/id6812768622   (no region code — the old v3 QR had /kr/)
    qr-android-beta.svg   https://aing-check.vercel.app/#android    (install section Android beta card — opens the
                          three-step guide on the phone; SITE_URL in lib/site.ts + LINKS.android in data/fixtures.ts)

Spec (both):
    error correction M, quiet zone 4 modules, single <path> (SvgPathImage)
    modules #12131C on a #F2F3F7 tile (full-bleed rect, quiet zone included)
    viewBox is in modules; width/height = modules x 4 px so the <img> has a sane intrinsic size.
    The lib's one-square-per-module subpaths are merged into horizontal runs (same shapes, about
    half the bytes); a self-check re-expands the runs and compares them with the QR matrix.

Output is deterministic (same payload -> same bytes), so the ?v= hash in assets.json only
changes when the payload or the styling changes. build-assets.mjs (brand group) calls this.
"""
import os
import re
import sys

import qrcode
import qrcode.image.svg

# (payload, output file name) — the App Store one first; its bytes must not change.
TARGETS = [
    ("https://apps.apple.com/app/id6812768622", "qr-appstore.svg"),
    ("https://aing-check.vercel.app/#android", "qr-android-beta.svg"),
]
MODULE = "#12131C"
TILE = "#F2F3F7"
PX_PER_MODULE = 4

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "public", "assets", "brand")


class TilePathImage(qrcode.image.svg.SvgPathImage):
    background = TILE
    QR_PATH_STYLE = {
        "fill": MODULE,
        "fill-opacity": "1",
        "fill-rule": "nonzero",
        "stroke": "none",
        "shape-rendering": "crispEdges",
    }


def make(url: str, name: str) -> int:
    out = os.path.join(OUT_DIR, name)
    qr = qrcode.QRCode(
        version=None,
        error_correction=qrcode.constants.ERROR_CORRECT_M,
        box_size=10,  # 10 px = 1 unit in the qrcode lib -> viewBox in modules
        border=4,
        image_factory=TilePathImage,
    )
    qr.add_data(url)
    qr.make(fit=True)
    img = qr.make_image()
    svg = img.to_string(encoding="unicode")

    modules = qr.modules_count + 2 * 4
    px = modules * PX_PER_MODULE
    # The lib writes width/height in mm ("37mm"); replace with px so browsers get an intrinsic size.
    svg, n = re.subn(r'width="[^"]+" height="[^"]+"', f'width="{px}" height="{px}"', svg, count=1)
    if n != 1:
        print("make-qr: could not rewrite width/height", file=sys.stderr)
        return 1
    if f'viewBox="0 0 {modules} {modules}"' not in svg:
        print(f"make-qr: unexpected viewBox (want 0 0 {modules} {modules})", file=sys.stderr)
        return 1
    if MODULE not in svg or TILE not in svg:
        print("make-qr: colors missing from output", file=sys.stderr)
        return 1

    # Merge the lib's one-square-per-module subpaths into horizontal runs (same shapes, ~half the bytes).
    m = re.search(r' d="([^"]*)"', svg)
    squares = re.findall(r"M(\d+),(\d+)H(\d+)V(\d+)H(\d+)z", m.group(1)) if m else []
    if not squares or "".join(f"M{a},{b}H{c}V{d}H{e}z" for a, b, c, d, e in squares) != m.group(1):
        print("make-qr: unexpected path format from qrcode lib", file=sys.stderr)
        return 1
    cells = set()
    for a, b, c, d, e in squares:
        x, y = int(a), int(b)
        if (int(c), int(d), int(e)) != (x + 1, y + 1, x):
            print("make-qr: non-unit module square", file=sys.stderr)
            return 1
        cells.add((x, y))
    runs = []
    for y in sorted({y for _, y in cells}):
        xs = sorted(x for x, yy in cells if yy == y)
        start = prev = xs[0]
        for x in xs[1:] + [None]:
            if x is not None and x == prev + 1:
                prev = x
                continue
            runs.append(f"M{start},{y}h{prev - start + 1}v1h-{prev - start + 1}z")
            if x is not None:
                start = prev = x
    svg = svg.replace(m.group(0), f' d="{"".join(runs)}"', 1)

    # Self-check: the merged path covers exactly the dark modules of the QR matrix (with border).
    matrix = qr.get_matrix()
    want = {(x, y) for y, row in enumerate(matrix) for x, on in enumerate(row) if on}
    got = set()
    for x0, y, n in re.findall(r"M(\d+),(\d+)h(\d+)v1h-\d+z", "".join(runs)):
        got.update((int(x0) + i, int(y)) for i in range(int(n)))
    if got != want or len(matrix) != modules:
        print(f"make-qr: module mismatch after merge ({len(got ^ want)} cells differ)", file=sys.stderr)
        return 1

    os.makedirs(OUT_DIR, exist_ok=True)
    data = ('<?xml version="1.0" encoding="UTF-8"?>\n' + svg + "\n").encode("utf-8")
    with open(out, "wb") as f:
        f.write(data)
    print(f"make-qr: {os.path.relpath(out, ROOT)} {len(data)} B, version {qr.version}, {modules}x{modules} modules, {url}")
    return 0


def main() -> int:
    for url, name in TARGETS:
        code = make(url, name)
        if code != 0:
            return code
    return 0


if __name__ == "__main__":
    sys.exit(main())
