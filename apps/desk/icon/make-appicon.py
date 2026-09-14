#!/usr/bin/env python3
"""Generate a Dev Desk app icon variant from source art that ships a preview checkerboard.

    python3 apps/desk/icon/make-appicon.py [--variant light|dark] [--source <png>]

The source art is exported with an opaque checkerboard behind it, so the whole job is keying that
out without eating the icon. The first version of this script flood-filled from the edges through
"near-grey" pixels, which worked only because that art was blue: every grey was background. The
2026-09-13 art is a cream tile with a near-black twin, and both of those are grey — the old rule
would have keyed out the icon itself.

So the key is the checkerboard's **pattern**, not its colour. A checker pixel differs from the
pixels half a period away on BOTH sides; a pixel inside the tile does not differ from at least one
of them. That holds for any icon colour, and it stops at the tile's edge instead of eating half a
period of it.

The two variants run that same key over different art and land in different places, because they
are read by different machinery. `light` is the bundle's shipped icon, so it fills the ten named
PNGs of `AppIcon.appiconset` that `ASSETCATALOG_COMPILER_APPICON_NAME` points at. `dark` is loaded
at runtime by `NSImage(named:)` and handed to `NSWorkspace.setIcon`, which wants one image at the
largest size it will ever be drawn, so it fills a plain image set instead. Keeping `light` the
default means the no-argument invocation still writes exactly the shipped set, byte for byte.
"""

from __future__ import annotations

import argparse
import json
from collections import deque
from dataclasses import dataclass
from pathlib import Path
from typing import Callable

import numpy as np
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parents[3]
ICON_DIR = ROOT / "apps/desk/icon"
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


def checker_period(gray: np.ndarray) -> int:
    """The checker square's size in pixels, from the autocorrelation of a border row."""
    row = gray[3] - gray[3].mean()
    ac = np.correlate(row, row, mode="full")[len(row) - 1:]
    ac = ac / ac[0]
    best, best_value = 0, 0.0
    for i in range(6, 80):
        if ac[i] > ac[i - 1] and ac[i] >= ac[i + 1] and float(ac[i]) > best_value:
            best, best_value = i, float(ac[i])
    if best == 0:
        raise SystemExit("no checkerboard period found in the source art")
    return best


def checker_mask(gray: np.ndarray, period: int, threshold: float = 20.0) -> np.ndarray:
    """Pixels that look like checkerboard: different from BOTH neighbours half a period away.

    Inside the tile, at least one of the two comparisons lands in the same flat region, so the
    minimum is small. At the tile's edge the inward comparison is flat, which is what holds the
    boundary.
    """
    shift = max(period // 2, 1)
    horizontal = np.minimum(np.abs(gray - np.roll(gray, shift, axis=1)),
                            np.abs(gray - np.roll(gray, -shift, axis=1)))
    vertical = np.minimum(np.abs(gray - np.roll(gray, shift, axis=0)),
                          np.abs(gray - np.roll(gray, -shift, axis=0)))
    return np.maximum(horizontal, vertical) > threshold


def flood_from_edges(candidate: np.ndarray) -> np.ndarray:
    """Only checkerboard reachable from the border is background; a checker-looking patch inside
    the tile is not."""
    h, w = candidate.shape
    visited = np.zeros((h, w), dtype=bool)
    queue: deque = deque()

    def push(y: int, x: int) -> None:
        if 0 <= y < h and 0 <= x < w and not visited[y, x] and candidate[y, x]:
            visited[y, x] = True
            queue.append((y, x))

    for x in range(w):
        push(0, x)
        push(h - 1, x)
    for y in range(h):
        push(y, 0)
        push(y, w - 1)
    while queue:
        y, x = queue.popleft()
        push(y - 1, x)
        push(y + 1, x)
        push(y, x - 1)
        push(y, x + 1)
    return visited


def close_towards_edges(background: np.ndarray, period: int) -> np.ndarray:
    """The keyed mask catches the checker's crossings, not the flat middle of each square. Closing
    by a period fills those holes; re-anchoring to the border undoes any bleed over the tile."""
    radius = max(period, 3) | 1
    image = Image.fromarray((background * 255).astype(np.uint8))
    closed = image.filter(ImageFilter.MaxFilter(size=radius)).filter(ImageFilter.MinFilter(size=radius))
    return flood_from_edges((np.array(closed) > 127) | background)


def largest_component(mask: np.ndarray) -> np.ndarray:
    """The tile is one connected shape. Anything else the key called "icon" — a checker square the
    pattern test could not decide, a speck in the shadow — is background, and at 1024 px a speck
    becomes a light halo the Dock composites as a grey fringe.
    """
    h, w = mask.shape
    seen = np.zeros((h, w), dtype=bool)
    best: list[tuple[int, int]] = []
    for start_y in range(h):
        for start_x in range(w):
            if not mask[start_y, start_x] or seen[start_y, start_x]:
                continue
            component: list[tuple[int, int]] = []
            queue = deque([(start_y, start_x)])
            seen[start_y, start_x] = True
            while queue:
                y, x = queue.popleft()
                component.append((y, x))
                for ny, nx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
                    if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and not seen[ny, nx]:
                        seen[ny, nx] = True
                        queue.append((ny, nx))
            if len(component) > len(best):
                best = component
    kept = np.zeros((h, w), dtype=bool)
    if best:
        ys, xs = zip(*best)
        kept[np.array(ys), np.array(xs)] = True
    return kept


def alpha_from_shadow(gray: np.ndarray, background: np.ndarray, period: int) -> np.ndarray:
    """What is left of the background once the checker is gone: the art's own drop shadow.

    The lit checker square is the local maximum, so the shadow is how far that maximum has fallen
    below the far field — no phase fitting, which would drift over 1254 px of a noisy export.
    """
    local_max = np.array(Image.fromarray(gray.astype(np.uint8))
                         .filter(ImageFilter.MaxFilter(size=(period * 2) | 1))).astype(float)
    border = np.zeros_like(background)
    border[:period, :] = True
    border[-period:, :] = True
    border[:, :period] = True
    border[:, -period:] = True
    far_field = float(np.median(local_max[border & background]))
    alpha = np.clip(1.0 - local_max / max(far_field, 1e-6), 0.0, 1.0)
    alpha[alpha < 0.02] = 0.0
    return (alpha * 255).astype(np.uint8)


def resize_to_size(rgba: np.ndarray, target_size: int) -> np.ndarray:
    """Resize RGBA on premultiplied alpha, then unpremultiply — haloing otherwise."""
    if rgba.shape[0] == target_size:
        return rgba.copy()
    alpha = rgba[:, :, 3].astype(np.float32) / 255.0
    premultiplied = np.concatenate([rgba[:, :, :3].astype(np.float32) * alpha[:, :, None],
                                    alpha[:, :, None] * 255], axis=2).astype(np.uint8)
    resized = np.array(Image.fromarray(premultiplied)
                       .resize((target_size, target_size), Image.Resampling.LANCZOS)).astype(np.float32)
    alpha_resized = resized[:, :, 3] / 255.0
    with np.errstate(divide="ignore", invalid="ignore"):
        rgb = resized[:, :, :3] / (alpha_resized[:, :, None] + 1e-10)
    rgb = np.clip(rgb, 0, 255)
    rgb[alpha_resized < 0.02] = 0
    return np.concatenate([rgb.astype(np.uint8),
                           (alpha_resized * 255).astype(np.uint8)[:, :, None]], axis=2)


def clear_outside_body(rgba: np.ndarray, padding: int = 3) -> np.ndarray:
    """Empty everything beyond the tile, so a stray keyed pixel can never become a grey grid in the
    Dock (the contract check-appicon.py enforces).

    The bound is the tile's own box, not a fixed margin: a fixed 90 px frame with 120 px corners was
    written for art whose tile started at 126 px, and this art's starts at 88 — the corner blocks
    would have cut the tile's own rounded corners off.
    """
    out = rgba.copy()
    opaque = out[:, :, 3] > 200
    if not opaque.any():
        raise SystemExit("nothing opaque in the keyed art")
    ys, xs = np.where(opaque)
    top, bottom = max(int(ys.min()) - padding, 0), min(int(ys.max()) + padding + 1, out.shape[0])
    left, right = max(int(xs.min()) - padding, 0), min(int(xs.max()) + padding + 1, out.shape[1])
    keep = np.zeros(out.shape[:2], dtype=bool)
    keep[top:bottom, left:right] = True
    out[~keep] = 0
    return out


def center_on_grid(rgba: np.ndarray, tile_size: int = 824, canvas: int = 1024) -> np.ndarray:
    """Put the tile on Apple's icon grid: an 824 px squircle centred on 1024, ~100 px clear all round.

    `clear_outside_body` bounds the tile but does not place it: the art is exported edge-to-edge, so
    the master came out 880 px wide with uneven margins. macOS does not rescale an app icon — it draws
    the pixels it is given — so that tile sat oversized in the Dock, and its baked corner radius read
    as the wrong curve next to neighbours whose radius is cut for 824.

    Scaling by the longest side, not by width and height separately, keeps the tile's aspect ratio;
    the resize runs on premultiplied alpha for the same reason `resize_to_size` does, or the
    transparent surround bleeds into the edge as a halo.
    """
    opaque = rgba[:, :, 3] > 40
    if not opaque.any():
        raise SystemExit("nothing opaque to centre on the icon grid")
    ys, xs = np.where(opaque)
    top, bottom = int(ys.min()), int(ys.max()) + 1
    left, right = int(xs.min()), int(xs.max()) + 1
    cropped = rgba[top:bottom, left:right]

    height, width = cropped.shape[:2]
    scale = tile_size / max(height, width)
    new_width, new_height = max(round(width * scale), 1), max(round(height * scale), 1)

    alpha = cropped[:, :, 3].astype(np.float32) / 255.0
    premultiplied = np.concatenate([cropped[:, :, :3].astype(np.float32) * alpha[:, :, None],
                                    alpha[:, :, None] * 255], axis=2).astype(np.uint8)
    resized = np.array(Image.fromarray(premultiplied)
                       .resize((new_width, new_height), Image.Resampling.LANCZOS)).astype(np.float32)
    alpha_resized = resized[:, :, 3] / 255.0
    with np.errstate(divide="ignore", invalid="ignore"):
        rgb = resized[:, :, :3] / (alpha_resized[:, :, None] + 1e-10)
    rgb = np.clip(rgb, 0, 255)
    rgb[alpha_resized < 0.02] = 0
    tile = np.concatenate([rgb.astype(np.uint8),
                           (alpha_resized * 255).astype(np.uint8)[:, :, None]], axis=2)

    out = np.zeros((canvas, canvas, 4), dtype=np.uint8)
    offset_y, offset_x = (canvas - new_height) // 2, (canvas - new_width) // 2
    out[offset_y:offset_y + new_height, offset_x:offset_x + new_width] = tile
    return out


def write_appiconset(master: np.ndarray) -> None:
    """The ten PNGs the app icon set names, every one cut from the single 1024 master."""
    for name, size in EXPECTED.items():
        Image.fromarray(resize_to_size(master, size)).save(ICONSET / name, "PNG")
    print(f"Wrote {len(EXPECTED)} files to {ICONSET.relative_to(ROOT)}")


def write_dark_imageset(master: np.ndarray) -> None:
    """One 1024 PNG in a single-scale image set, with the Contents.json Xcode would have written.

    Single scale — no 1x/2x/3x slots — for two reasons: `NSImage(named:)` then reports a 1024x1024
    image, which is the size `NSWorkspace.setIcon` and the Dock both want; and the slots a 1x-only
    set would leave empty are what actool reports as an unassigned child, a warning for nothing.
    """
    DARK_IMAGESET.mkdir(parents=True, exist_ok=True)
    Image.fromarray(master).save(DARK_IMAGESET / DARK_IMAGE, "PNG")
    contents = {
        "images": [{"filename": DARK_IMAGE, "idiom": "universal"}],
        "info": {"author": "xcode", "version": 1},
        "properties": {"template-rendering-intent": "original"},
    }
    (DARK_IMAGESET / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n")
    print(f"Wrote {DARK_IMAGE} + Contents.json to {DARK_IMAGESET.relative_to(ROOT)}")


@dataclass(frozen=True)
class Variant:
    """Where one variant reads its art, where its 1024 master lands, and who consumes it."""

    source: Path
    master: Path
    write: Callable[[np.ndarray], None]


VARIANTS = {
    "light": Variant(ICON_DIR / "source-light-1254.png", ICON_DIR / "AppIcon-1024.png", write_appiconset),
    "dark": Variant(ICON_DIR / "source-dark-1254.png", ICON_DIR / DARK_IMAGE, write_dark_imageset),
}


def main() -> None:
    parser = argparse.ArgumentParser(description="Build one app icon variant from source art.")
    parser.add_argument("--variant", choices=sorted(VARIANTS), default="light",
                        help="light fills AppIcon.appiconset, dark fills AppIconDark.imageset")
    parser.add_argument("--source", type=Path, default=None,
                        help="1254x1254 source art with a preview checkerboard behind it")
    args = parser.parse_args()
    variant = VARIANTS[args.variant]
    source = args.source or variant.source

    rgb = np.array(Image.open(source).convert("RGB"), dtype=np.uint8)
    if rgb.shape[:2] != (1254, 1254):
        raise SystemExit(f"expected 1254x1254 source art, got {rgb.shape[1]}x{rgb.shape[0]}")
    gray = rgb.astype(float).mean(axis=2)

    period = checker_period(gray)
    print(f"Checker period: {period} px")

    background = close_towards_edges(flood_from_edges(checker_mask(gray, period)), period)
    # A checker square touching the tile shares an edge with it, and where the tile's own colour is
    # close to the lit square the pattern test cannot separate them — the square joins the body as a
    # nub on the silhouette. Opening (erode, then dilate) takes the nubs and leaves the tile.
    body_mask = Image.fromarray(((~background) * 255).astype(np.uint8))
    opened = body_mask.filter(ImageFilter.MinFilter(size=7)).filter(ImageFilter.MaxFilter(size=7))
    body = largest_component((np.array(opened) > 127) & ~background)
    background = ~body
    print(f"  background {background.sum()} px · icon body {body.sum()} px")
    if not 0.2 < background.mean() < 0.9:
        raise SystemExit(f"keying looks wrong: {background.mean():.0%} of the art was called background")

    rgba = np.zeros((*gray.shape, 4), dtype=np.uint8)
    rgba[~background, :3] = rgb[~background]
    rgba[~background, 3] = 255
    rgba[background, 3] = alpha_from_shadow(gray, background, period)[background]

    master = center_on_grid(clear_outside_body(resize_to_size(rgba, 1024)))
    Image.fromarray(master).save(variant.master, "PNG")
    print(f"Wrote {variant.master.relative_to(ROOT)}")

    variant.write(master)
    print("Now run: python3 apps/desk/icon/check-appicon.py")


if __name__ == "__main__":
    main()
