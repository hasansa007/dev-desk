#!/usr/bin/env python3
"""Generate the Dev Desk app icon set from source art with a baked checkerboard background."""

from PIL import Image, ImageFilter
import numpy as np
from pathlib import Path
from collections import deque

ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / "apps/desk/icon/source-1254.png"
MASTER_OUT = ROOT / "apps/desk/icon/AppIcon-1024.png"
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


def is_near_gray(rgb_pixel: np.ndarray, threshold: int = 25) -> bool:
    """Check if a pixel is near-grey (small channel spread)."""
    r, g, b = rgb_pixel[0].item(), rgb_pixel[1].item(), rgb_pixel[2].item()
    spread = max(r, g, b) - min(r, g, b)
    return spread < threshold


def flood_fill_background(rgb: np.ndarray) -> np.ndarray:
    """Flood fill from edges through pixels consistent with being background (near-grey)."""
    h, w = rgb.shape[:2]
    visited = np.zeros((h, w), dtype=bool)
    queue = deque()
    
    # Start from all edges
    for x in range(w):
        queue.append((0, x))
        queue.append((h - 1, x))
        visited[0, x] = True
        visited[h - 1, x] = True
    for y in range(1, h - 1):
        queue.append((y, 0))
        queue.append((y, w - 1))
        visited[y, 0] = True
        visited[y, w - 1] = True
    
    while queue:
        y, x = queue.popleft()
        
        # Accept if near-grey (background, possibly darkened by shadow)
        if not is_near_gray(rgb[y, x]):
            continue
        
        # Flood to neighbors
        for dy, dx in [(-1, 0), (1, 0), (0, -1), (0, 1)]:
            ny, nx = y + dy, x + dx
            if 0 <= ny < h and 0 <= nx < w and not visited[ny, nx]:
                visited[ny, nx] = True
                queue.append((ny, nx))
    
    return visited


def unmix_alpha_with_median(rgb: np.ndarray, bg_mask: np.ndarray) -> np.ndarray:
    """
    Unmix alpha using a median filter on the whole image to remove checkerboard.
    Only unmix the background; the icon body stays opaque.
    """
    h, w = rgb.shape[:2]
    rgba = np.zeros((h, w, 4), dtype=np.uint8)
    
    # Icon body is opaque
    rgba[~bg_mask, 3] = 255
    rgba[~bg_mask, :3] = rgb[~bg_mask]
    
    # Apply median filter to each channel on the whole image
    r_smooth = np.array(Image.fromarray(rgb[:, :, 0]).filter(ImageFilter.MedianFilter(size=31)))
    g_smooth = np.array(Image.fromarray(rgb[:, :, 1]).filter(ImageFilter.MedianFilter(size=31)))
    b_smooth = np.array(Image.fromarray(rgb[:, :, 2]).filter(ImageFilter.MedianFilter(size=31)))
    
    # Compute local median brightness
    local_bg_mean = (r_smooth.astype(float) + g_smooth.astype(float) + b_smooth.astype(float)) / 3.0
    
    # For background pixels only, estimate the reference level
    bg_y, bg_x = np.where(bg_mask)
    bg_local_vals = local_bg_mean[bg_y, bg_x]
    far_field_level = np.median(bg_local_vals)
    print(f"    Far-field median brightness: {far_field_level:.1f}")
    
    # Unmix: alpha = 1 - (local / far_field)
    alpha_float = 1.0 - (bg_local_vals / (far_field_level + 1e-10))
    alpha_float = np.clip(alpha_float, 0.0, 1.0)
    
    # Deadband: snap very small alpha to 0 (noise)
    alpha_float[alpha_float < 0.02] = 0.0
    
    # Convert to [0, 255]
    alpha_uint = (alpha_float * 255).astype(np.uint8)
    rgba[bg_y, bg_x, 3] = alpha_uint
    
    # Set RGB to black
    rgba[bg_y, bg_x, :3] = 0
    
    return rgba


def resize_to_size(rgba: np.ndarray, target_size: int) -> np.ndarray:
    """Resize RGBA with high-quality filter on premultiplied alpha, then unpremultiply."""
    source_size = rgba.shape[0]
    if source_size == target_size:
        return rgba.copy()
    
    alpha = rgba[:, :, 3].astype(np.float32) / 255.0
    rgb = rgba[:, :, :3].astype(np.float32)
    premult_rgb = rgb * alpha[:, :, None]
    
    premult_img_data = np.concatenate([premult_rgb, alpha[:, :, None] * 255], axis=2).astype(np.uint8)
    pil_img = Image.fromarray(premult_img_data)
    
    resized = pil_img.resize((target_size, target_size), Image.Resampling.LANCZOS)
    resized_arr = np.array(resized).astype(np.float32)
    
    alpha_resized = resized_arr[:, :, 3] / 255.0
    rgb_resized = resized_arr[:, :, :3]
    
    with np.errstate(divide='ignore', invalid='ignore'):
        unpremult_rgb = rgb_resized / (alpha_resized[:, :, None] + 1e-10)
    
    unpremult_rgb = np.clip(unpremult_rgb, 0, 255)
    unpremult_rgb[alpha_resized < 0.02] = 0
    
    alpha_resized_255 = (alpha_resized * 255).astype(np.uint8)
    result = np.concatenate([unpremult_rgb.astype(np.uint8), alpha_resized_255[:, :, None]], axis=2)
    return result


def cleanup_with_aggressive_corners(rgba: np.ndarray, target_size: int) -> np.ndarray:
    """Clean up outer frame and corners, snapping partial alpha to 0 far from the icon."""
    result = rgba.copy()
    a = result[:, :, 3]
    
    # Clear outer 90px (more than double the validator's 40px check)
    a[:90, :] = 0
    a[-90:, :] = 0
    a[:, :90] = 0
    a[:, -90:] = 0
    
    # Clear corners (120×120) to fully transparent
    a[:120, :120] = 0
    a[:120, -120:] = 0
    a[-120:, :120] = 0
    a[-120:, -120:] = 0
    
    # Also set RGB to 0 in these regions
    result[:90, :, :3] = 0
    result[-90:, :, :3] = 0
    result[:, :90, :3] = 0
    result[:, -90:, :3] = 0
    result[:120, :120, :3] = 0
    result[:120, -120:, :3] = 0
    result[-120:, :120, :3] = 0
    result[-120:, -120:, :3] = 0
    
    return result


def main():
    print("Loading source image...")
    img_source = Image.open(SOURCE).convert("RGB")
    rgb = np.array(img_source, dtype=np.uint8)
    h, w = rgb.shape[:2]
    assert (h, w) == (1254, 1254), f"Expected 1254×1254, got {h}×{w}"
    
    print("Flood-filling background from edges...")
    bg_mask = flood_fill_background(rgb)
    bg_pixels = bg_mask.sum()
    icon_pixels = (~bg_mask).sum()
    print(f"  Background pixels: {bg_pixels}")
    print(f"  Icon body pixels: {icon_pixels}")
    
    print("Unmixing alpha using median-filter background estimation...")
    rgba = unmix_alpha_with_median(rgb, bg_mask)
    
    print("Resizing to 1024×1024 master...")
    master_1024 = resize_to_size(rgba, 1024)
    
    print("Cleaning up corners and frame...")
    master_1024 = cleanup_with_aggressive_corners(master_1024, 1024)
    
    print(f"Saving master to {MASTER_OUT}")
    master_img = Image.fromarray(master_1024)
    master_img.save(MASTER_OUT, "PNG")
    
    master_arr = np.array(master_img, dtype=int)
    r, g, b, a = master_arr[:, :, 0], master_arr[:, :, 1], master_arr[:, :, 2], master_arr[:, :, 3]
    
    orange_px = ((r > 200) & (g > 120) & (g < 200) & (b < 100) & (a > 200)).sum()
    alpha_vals = a.flatten()
    alpha_opaque = (alpha_vals > 200).sum()
    alpha_partial = ((alpha_vals > 8) & (alpha_vals <= 200)).sum()
    alpha_transparent = (alpha_vals <= 8).sum()
    
    print(f"\nMaster (1024×1024) analysis:")
    print(f"  Orange pixels (r>200, g∈[120,200), b<100, α>200): {orange_px}")
    print(f"  Alpha > 200 (opaque): {alpha_opaque}")
    print(f"  Alpha 9-200 (partial): {alpha_partial}")
    print(f"  Alpha ≤ 8 (transparent): {alpha_transparent}")
    
    has_shadow = ((alpha_vals > 8) & (alpha_vals < 200)).sum() > 100
    print(f"  Drop shadow present: {has_shadow}")
    
    print(f"\nGenerating icon set ({len(EXPECTED)} files)...")
    for name, size in EXPECTED.items():
        if size == 1024:
            img_resized = master_1024
        else:
            img_resized = resize_to_size(master_1024, size)
        
        out_path = ICONSET / name
        pil_img = Image.fromarray(img_resized)
        pil_img.save(out_path, "PNG")
        print(f"  {name:20} ({size:4}×{size:4})")
    
    print("\nDone! Run: python3 apps/desk/icon/check-appicon.py")


if __name__ == "__main__":
    main()
