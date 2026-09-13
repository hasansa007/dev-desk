#!/usr/bin/env python3
"""Contract for the Dev Desk app icon set.

Run from the repository root:  python3 apps/desk/icon/check-appicon.py

It checks the ten PNGs the asset catalog names actually exist at the right pixel sizes, carry a real
alpha channel, and were cut from the 2026-09 source art (the terminal screen with the orange list
bar). The background checks are the point: the source art ships an opaque preview checkerboard, so a
conversion that forgets to key it out looks correct in Preview and ships a grey grid in the Dock.
"""
import json
import sys
from pathlib import Path

try:
    from PIL import Image
except ImportError:  # pragma: no cover
    sys.exit("Pillow is required: python3 -m pip install Pillow")

import numpy as np

ROOT = Path(__file__).resolve().parents[3]
ICONSET = ROOT / "apps/desk/DevDesk/Resources/Assets.xcassets/AppIcon.appiconset"

EXPECTED = {
    "icon_16x16.png": 16,
    "icon_16x16@2x.png": 32,
    "icon_32x32.png": 32,
    "icon_32x32@2x.png": 64,
    "icon_128x128.png": 128,
    "icon_128x128@2x.png": 256,
    "icon_256x256.png": 256,
    "icon_256x256@2x.png": 512,
    "icon_512x512.png": 512,
    "icon_512x512@2x.png": 1024,
}

failures: list[str] = []


def fail(msg: str) -> None:
    failures.append(msg)


def load(name: str) -> Image.Image:
    return Image.open(ICONSET / name).convert("RGBA")


# 1. Contents.json still names exactly these files at these sizes.
contents = json.loads((ICONSET / "Contents.json").read_text())
named = {}
for entry in contents["images"]:
    px = int(float(entry["size"].split("x")[0]) * int(entry["scale"].rstrip("x")))
    named[entry["filename"]] = px
if named != EXPECTED:
    fail(f"Contents.json no longer matches the expected filename/size map: {named}")

# 2. Every file exists at its exact size with an alpha channel.
for name, px in EXPECTED.items():
    path = ICONSET / name
    if not path.exists():
        fail(f"{name}: missing")
        continue
    im = Image.open(path)
    if im.format != "PNG":
        fail(f"{name}: format is {im.format}, expected PNG")
    if im.size != (px, px):
        fail(f"{name}: size is {im.size}, expected ({px}, {px})")
    if "A" not in im.getbands():
        fail(f"{name}: no alpha channel (mode {im.mode})")

if failures:
    print("\n".join("FAIL  " + f for f in failures))
    sys.exit(1)

# 3. The 1024 master carries the contract.
master = np.array(load("icon_512x512@2x.png")).astype(int)
alpha = master[:, :, 3]
rgb = master[:, :, :3]
R, G, B = rgb[:, :, 0], rgb[:, :, 1], rgb[:, :, 2]

for label, patch in (
    ("top-left", alpha[0:70, 0:70]),
    ("top-right", alpha[0:70, -70:]),
    ("bottom-left", alpha[-70:, 0:70]),
    ("bottom-right", alpha[-70:, -70:]),
):
    if patch.max() != 0:
        fail(f"master: {label} corner is not fully transparent (max alpha {patch.max()})")

if alpha[512, 512] < 250:
    fail(f"master: centre pixel is not opaque (alpha {alpha[512, 512]})")

# The blue rounded square, scaled from the source art's bbox of (126,133)-(1127,1123) at 1254px.
blue = (B - R > 60) & (alpha > 200)
if blue.sum() < 200_000:
    fail(f"master: too little blue body found ({blue.sum()} px)")
else:
    ys, xs = np.where(blue)
    got = (xs.min(), ys.min(), xs.max(), ys.max())
    want = (103, 109, 920, 917)
    if any(abs(g - w) > 16 for g, w in zip(got, want)):
        fail(f"master: body bbox {got} is not within 16px of the source geometry {want}")

# The orange list bar is what makes this the new art rather than the 2026-09-13 icon.
orange = (R > 200) & (G > 120) & (G < 200) & (B < 100) & (alpha > 200)
if orange.sum() < 3000:
    fail(f"master: orange list bar missing or too small ({orange.sum()} px, expected ~6100)")

# Nothing opaque and light may live outside the body: that is what a leftover checkerboard looks
# like. A baked drop shadow is allowed, but it has to be dark.
outside = np.ones_like(alpha, dtype=bool)
outside[105 - 8 : 917 + 8, 101 - 8 : 918 + 8] = False
luma = (0.299 * R + 0.587 * G + 0.114 * B)
bad = outside & (alpha > 8) & (luma > 150)
if bad.sum() > 0:
    ys, xs = np.where(bad)
    fail(
        f"master: {bad.sum()} light pixels outside the icon body (checkerboard remnants?), "
        f"first at ({xs[0]}, {ys[0]}) rgba={tuple(master[ys[0], xs[0]])}"
    )

# A hard binary cutout has almost no partial coverage; real antialiasing has thousands of pixels.
partial = ((alpha > 8) & (alpha < 247)).sum()
if partial < 1200:
    fail(f"master: edges are not antialiased ({partial} partially transparent pixels)")

# 4. The derived sizes came from that same master.
for name, px in EXPECTED.items():
    im = np.array(load(name)).astype(int)
    a = im[:, :, 3]
    edge = max(1, px // 16)
    if a[0:edge, 0:edge].max() != 0:
        fail(f"{name}: top-left corner is not transparent")
    if a[px // 2, px // 2] < 250:
        fail(f"{name}: centre pixel is not opaque (alpha {a[px // 2, px // 2]})")
    if px >= 128:
        r, g, b = im[:, :, 0], im[:, :, 1], im[:, :, 2]
        o = ((r > 200) & (g > 120) & (g < 200) & (b < 100) & (a > 200)).sum()
        if o < 20:
            fail(f"{name}: orange list bar did not survive the downscale ({o} px)")

if failures:
    print("\n".join("FAIL  " + f for f in failures))
    sys.exit(1)

print(f"OK  {len(EXPECTED)} icons, transparent background, new source art, antialiased edges")
