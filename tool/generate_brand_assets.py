#!/usr/bin/env python3
"""Generate the StreamBox launcher icon + Android TV banner.

Brand (from Figma "StreamBox — Provider App" + lib/theme/app_theme.dart):
  gradient #FF7700 (top-left) -> #F03A02 (bottom-right), dark #09090D.
Icon: full-bleed diagonal gradient + clean white play triangle, drawn at
4x supersampling and downscaled for smooth edges. The triangle is a plain
geometric play mark (the logo) — not an Iconsax glyph.
Banner: dark background + gradient play mark + "StreamBox" wordmark.
"""
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

BRAND = (0xFF, 0x77, 0x00)
BRAND_END = (0xF0, 0x3A, 0x02)
DARK = (0x09, 0x09, 0x0D)
WHITE = (255, 255, 255)
SS = 4  # supersampling factor


def diagonal_gradient(size, c1, c2):
    """size x size RGB image, c1 top-left -> c2 bottom-right."""
    x = np.linspace(0, 1, size)
    y = np.linspace(0, 1, size)
    t = (np.add.outer(y, x) / 2.0)[..., None]  # 0 top-left, 1 bottom-right
    a = np.array(c1, dtype=np.float64)
    b = np.array(c2, dtype=np.float64)
    img = (a + (b - a) * t).astype(np.uint8)
    return Image.fromarray(img, "RGB")


def rounded_triangle_mask(size, cx, cy, width, height, corner_blur):
    """L-mode mask with a white rounded-corner play triangle.

    The triangle points right; corners are rounded by blurring the mask
    and re-thresholding. Optical centering: shift slightly right.
    """
    mask = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(mask)
    hw, hh = width / 2, height / 2
    pts = [
        (cx - hw, cy - hh),  # top-left
        (cx - hw, cy + hh),  # bottom-left
        (cx + hw, cy),  # tip (right)
    ]
    d.polygon(pts, fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(corner_blur))
    mask = mask.point(lambda v: 255 if v >= 128 else 0)
    return mask


def make_icon(path, size=1024):
    s = size * SS
    img = diagonal_gradient(s, BRAND, BRAND_END)
    # Triangle: ~40% of the canvas, optically centered (shifted right ~2%).
    cx, cy = s * 0.52, s * 0.50
    mask = rounded_triangle_mask(
        s, cx, cy, width=s * 0.38, height=s * 0.44, corner_blur=10 * SS
    )
    white = Image.new("RGB", (s, s), WHITE)
    img.paste(white, (0, 0), mask)
    img = img.resize((size, size), Image.LANCZOS)
    img.save(path, "PNG")
    print(f"wrote {path} {img.size}")


def make_banner(path, width=320, height=180):
    s = SS
    w, h = width * s, height * s
    img = Image.new("RGB", (w, h), DARK)
    d = ImageDraw.Draw(img)

    # Gradient play mark: rounded square, left side, vertically centered.
    mark = 64 * s
    mx, my = 28 * s, (h - mark) // 2
    grad = diagonal_gradient(mark, BRAND, BRAND_END)
    radius = 16 * s
    m = Image.new("L", (mark, mark), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, mark, mark], radius, fill=255)
    tri = rounded_triangle_mask(
        mark, mark * 0.53, mark * 0.50,
        width=mark * 0.38, height=mark * 0.44, corner_blur=3 * s,
    )
    grad.paste(WHITE, (0, 0), tri)
    img.paste(grad, (mx, my), m)

    # Wordmark: Inter, white, vertically centered with the mark.
    # Auto-fit: shrink the font until "StreamBox" fits the space right
    # of the mark (with a right margin).
    max_text_w = w - (mx + mark + 16 * s) - 16 * s
    font_size = 44 * s
    while True:
        font = ImageFont.truetype(
            "assets/fonts/Inter-Variable.ttf", font_size
        )
        bbox = d.textbbox(
            (0, 0), "StreamBox", font=font, stroke_width=1 * s
        )
        if bbox[2] - bbox[0] <= max_text_w or font_size <= 10 * s:
            break
        font_size -= 2 * s
    tx = mx + mark + 16 * s
    # Pillow anchors text by its top; center using the text bbox.
    th = bbox[3] - bbox[1]
    ty = (h - th) // 2 - bbox[1]
    d.text((tx, ty), "StreamBox", font=font, fill=WHITE,
           stroke_width=1 * s, stroke_fill=WHITE)

    img = img.resize((width, height), Image.LANCZOS)
    img.save(path, "PNG")
    print(f"wrote {path} {img.size}")


if __name__ == "__main__":
    make_icon("assets/icon/icon.png")
    make_banner("assets/icon/tv_banner.png")
    # The Android TV banner drawable is a separate copy.
    Image.open("assets/icon/tv_banner.png").save(
        "android/app/src/main/res/drawable/tv_banner.png", "PNG"
    )
    print("wrote android/app/src/main/res/drawable/tv_banner.png (320, 180)")
