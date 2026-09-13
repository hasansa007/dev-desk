#!/usr/bin/env python3
"""Contract for the Dev Desk app icon set.

Run from the repository root:  python3 apps/desk/icon/check-appicon.py

It checks the ten PNGs the asset catalog names actually exist at the right pixel sizes, carry a real
alpha channel, and were cut from the current source art (the cream tile with three stacked list
bars — the middle one coral — a chevron, a dash, and code lines drawn inside every bar). The
background checks are the point: the source art ships an opaque preview checkerboard, so a
conversion that forgets to key it out looks correct in Preview and ships a grey grid in the Dock.

There are two icons to key, not one, and the same checkerboard traps both. `light` is the bundle's
shipped icon in `AppIcon.appiconset`. `dark` is the runtime variant in `AppIconDark.imageset` that
`NSWorkspace.setIcon` draws when the app icon setting resolves to dark — a single 1024 PNG. The
1024-master contract below runs over both: the light master shows a cream tile with dark bars, the
dark master a near-black tile with cream bars, and each ships a botched key as a grey Dock grid the
same way, so each is checked the same way against its own measured geometry and colour.
"""
import json
import sys
from pathlib import Path

try:
    from PIL import Image, ImageFilter
except ImportError:  # pragma: no cover
    sys.exit("Pillow is required: python3 -m pip install Pillow")

import numpy as np

ROOT = Path(__file__).resolve().parents[3]
ASSETS = ROOT / "apps/desk/DevDesk/Resources/Assets.xcassets"
ICONSET = ASSETS / "AppIcon.appiconset"
DARK_IMAGESET = ASSETS / "AppIconDark.imageset"
DARK_IMAGE = "AppIcon-dark-1024.png"

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

# The coral list bar, plus the small coral dash under the chevron, is what makes this the current
# art — light or dark, the coral is the same paint. It was orange in the first cut of this icon,
# which is exactly why the colour is asserted rather than assumed.
def coral_mask(R, G, B, A):
    return (R > 200) & (G > 90) & (G < 190) & (B > 60) & (B < 160) & (A > 200)


def check_master(tag, master, body):
    """The 1024-master contract, run over one variant.

    `body` names what the tile is made of and where it sits, because that is the one thing the two
    variants do not share: `light` is a cream tile (bright body, dark bars), `dark` a near-black tile
    (dark body, cream bars). Everything else — transparent corners and frame, opaque centre, coral
    bar, no light pixels or periodic alpha outside the body, antialiased edges — is a checkerboard
    contract that holds for both, so it is written once here.
    """
    alpha = master[:, :, 3]
    R, G, B = master[:, :, 0], master[:, :, 1], master[:, :, 2]

    for label, patch in (
        ("top-left", alpha[0:70, 0:70]),
        ("top-right", alpha[0:70, -70:]),
        ("bottom-left", alpha[-70:, 0:70]),
        ("bottom-right", alpha[-70:, -70:]),
    ):
        if patch.max() != 0:
            fail(f"{tag} master: {label} corner is not fully transparent (max alpha {patch.max()})")

    if alpha[512, 512] < 250:
        fail(f"{tag} master: centre pixel is not opaque (alpha {alpha[512, 512]})")

    # The rounded tile: the light art keys to a cream body of 483_965 px in bbox (71,68)-(950,943),
    # the dark art to a near-black body of 541_059 px in bbox (67,79)-(962,963). It replaced a blue
    # tile, so "is it blue" was the check that had to change; the light cream also catches the code
    # lines inside the dark bars, and vice versa, which is why both counts run high. Each floor stays
    # well under its own measurement so it fails on a body keyed away, not on the next art nudge.
    tile = body.mask(R, G, B, alpha)
    if tile.sum() < body.floor:
        fail(f"{tag} master: too little {body.name} body found ({tile.sum()} px, expected ~{body.expect})")
    else:
        ys, xs = np.where(tile)
        got = (int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max()))
        if any(abs(g - w) > 16 for g, w in zip(got, body.bbox)):
            fail(f"{tag} master: body bbox {got} is not within 16px of the source geometry {body.bbox}")

    # The tile's own corners must survive the keying: a fixed corner-clearing block once cut them off,
    # which is invisible at 1024 and obvious in the Dock. Each probe sits 70px along the diagonal from
    # a corner of that variant's bbox, only ~14px inside the rounded edge — near enough that a corner
    # the key clipped, or a block that squared it off, still fails here.
    for label, (y, x) in body.corners.items():
        if alpha[y, x] < 250:
            fail(f"{tag} master: the tile's {label} corner is missing (alpha {alpha[y, x]} at {(x, y)})")

    # Measured coral: 50_626 px on light, 39_073 px on dark (the darker surround the LANCZOS master
    # keeps cleaner leaves the dark bar a touch smaller). The cream code lines drawn inside the bar
    # already take their bite out of both.
    coral = coral_mask(R, G, B, alpha)
    if coral.sum() < body.coral_floor:
        fail(f"{tag} master: coral list bar missing or too small "
             f"({coral.sum()} px, expected ~{body.coral_expect})")

    # Nothing opaque and light may live outside the body: that is what a leftover checkerboard looks
    # like. A baked drop shadow is allowed, but it has to be dark. The window is the variant's own
    # measured bbox, since the dark tile keys ~4px wider than the light one.
    left, top, right, bottom = body.bbox
    outside = np.ones_like(alpha, dtype=bool)
    outside[top - 8 : bottom + 8, left - 8 : right + 8] = False
    luma = 0.299 * R + 0.587 * G + 0.114 * B
    bad = outside & (alpha > 8) & (luma > 150)
    if bad.sum() > 0:
        ys, xs = np.where(bad)
        fail(
            f"{tag} master: {bad.sum()} light pixels outside the icon body (checkerboard remnants?), "
            f"first at ({xs[0]}, {ys[0]}) rgba={tuple(master[ys[0], xs[0]])}"
        )

    # The checkerboard survives keying in two ways, and the light-pixel test above only catches one
    # of them. The other is the checker written into the ALPHA channel over dark pixels: invisible in
    # an RGB preview, invisible in the corners if the corners were snapped to zero, and a grey grid
    # the moment the Dock composites it. So the far field must be empty, and the background smooth.
    frame = np.zeros_like(alpha, dtype=bool)
    frame[:40, :] = True
    frame[-40:, :] = True
    frame[:, :40] = True
    frame[:, -40:] = True
    if alpha[frame].max() > 3:
        fail(
            f"{tag} master: the outer 40px frame is not empty (max alpha {alpha[frame].max()}, "
            f"{(alpha[frame] > 3).sum()} pixels above 3) — the background was not keyed out"
        )

    # A drop shadow is low frequency; a checkerboard is not. Compare the background's alpha against
    # its own local median: a shadow tracks it, a periodic grid does not.
    smooth = np.array(
        Image.fromarray(alpha.astype(np.uint8)).filter(ImageFilter.MedianFilter(size=15))
    ).astype(int)
    rough = outside & (np.abs(alpha - smooth) > 8)
    if rough.sum() > outside.sum() * 0.002:
        ys, xs = np.where(rough)
        fail(
            f"{tag} master: {rough.sum()} background pixels deviate from their local median "
            f"({rough.sum() / outside.sum():.1%} of the background) — that is a periodic pattern, "
            f"not a shadow; first at ({xs[0]}, {ys[0]}) alpha={alpha[ys[0], xs[0]]}"
        )

    # A hard binary cutout has almost no partial coverage; real antialiasing has thousands of pixels.
    partial = ((alpha > 8) & (alpha < 247)).sum()
    if partial < 1200:
        fail(f"{tag} master: edges are not antialiased ({partial} partially transparent pixels)")


class Body:
    """One variant's tile: how to recognise its paint, where it sits, and the counts it measures at.

    A tile 70px in from each bbox corner gives the four corner probes; `light` and `dark` key to
    slightly different boxes (dark ~4px wider), so each carries its own.
    """

    def __init__(self, name, mask, floor, expect, bbox, coral_floor, coral_expect):
        self.name = name
        self.mask = mask
        self.floor = floor
        self.expect = expect
        self.bbox = bbox
        self.coral_floor = coral_floor
        self.coral_expect = coral_expect
        left, top, right, bottom = bbox
        self.corners = {
            "top-left": (top + 70, left + 70),
            "top-right": (top + 70, right - 70),
            "bottom-left": (bottom - 70, left + 70),
            "bottom-right": (bottom - 70, right - 70),
        }


LIGHT_BODY = Body(
    name="cream",
    mask=lambda R, G, B, A: (R > 200) & (G > 200) & (B > 180) & (A > 200),
    floor=200_000, expect=484_000, bbox=(71, 68, 950, 943),
    coral_floor=25_000, coral_expect=50_600,
)
DARK_BODY = Body(
    name="near-black",
    mask=lambda R, G, B, A: (R < 70) & (G < 70) & (B < 70) & (A > 200),
    floor=350_000, expect=541_000, bbox=(67, 79, 962, 963),
    coral_floor=20_000, coral_expect=39_000,
)

# 3. The 1024 master of each variant carries the contract. The light master is one of the shipped
# icon-set PNGs; the dark master is the single PNG the image set holds.
master = np.array(load("icon_512x512@2x.png")).astype(int)
check_master("light", master, LIGHT_BODY)

dark_path = DARK_IMAGESET / DARK_IMAGE
if not dark_path.exists():
    fail(f"dark: {DARK_IMAGESET.name}/{DARK_IMAGE} is missing — run make-appicon.py --variant dark")
else:
    dark_im = Image.open(dark_path)
    if dark_im.format != "PNG":
        fail(f"dark: {DARK_IMAGE} format is {dark_im.format}, expected PNG")
    if dark_im.size != (1024, 1024):
        fail(f"dark: {DARK_IMAGE} size is {dark_im.size}, expected (1024, 1024)")
    if "A" not in dark_im.getbands():
        fail(f"dark: {DARK_IMAGE} has no alpha channel (mode {dark_im.mode})")
    # The image set must name that one PNG as its image, or NSImage(named:) finds nothing.
    dark_contents = json.loads((DARK_IMAGESET / "Contents.json").read_text())
    dark_named = {e.get("filename") for e in dark_contents["images"] if e.get("filename")}
    if dark_named != {DARK_IMAGE}:
        fail(f"dark: {DARK_IMAGESET.name}/Contents.json names {dark_named}, expected {{{DARK_IMAGE!r}}}")
    if not failures:
        check_master("dark", np.array(dark_im.convert("RGBA")).astype(int), DARK_BODY)

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
        # The same coral test as the master, deliberately: this ran on the older art's *orange*
        # range (b < 100) and kept "passing" on 2 stray pixels once the bar turned coral (b ≈ 114),
        # which is a check that no longer checks anything. Measured on the current set: 798 px at
        # 128, 3209 at 256, 12934 at 512, 50626 at 1024 — a floor of 250 clears the smallest size
        # threefold and still fails the moment the bar is washed out by the downscale.
        r, g, b = im[:, :, 0], im[:, :, 1], im[:, :, 2]
        o = coral_mask(r, g, b, a).sum()
        if o < 250:
            fail(f"{name}: coral list bar did not survive the downscale ({o} px)")

if failures:
    print("\n".join("FAIL  " + f for f in failures))
    sys.exit(1)

print(f"OK  {len(EXPECTED)} light icons + dark variant, transparent background, "
      f"new source art, antialiased edges")
