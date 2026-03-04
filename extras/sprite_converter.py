#!/usr/bin/env python3
"""
Sprite Converter for WordGrinder Statistics Addon

Converts a small PNG/image file into Lua sprite table data using Unicode
block characters for terminal rendering.

Two output modes:
  1. "full" — 1 pixel = 1 character cell, with shade encoding (# D M L .)
  2. "half" — 2 vertical pixels per character cell using half-block chars
             (▀ ▄ █ and space), effectively halving sprite height

Usage:
  python3 sprite_converter.py <image> [--mode full|half] [--threshold N]
                                       [--width W] [--invert]

The image should be a small grayscale or color PNG. Bright pixels become
filled blocks; dark pixels become empty. Use --invert if your source image
has a dark subject on a light background.

Output is printed as a Lua table you can paste into statistics.lua.
"""

import argparse
import sys
from PIL import Image


# Shade levels for full mode (darkest to brightest terminal character)
# Maps a 0.0–1.0 brightness value to an encoding character
SHADE_CHARS_FULL = [
    (0.00, "."),   # empty / transparent
    (0.15, "L"),   # ░ light shade
    (0.35, "M"),   # ▒ medium shade
    (0.60, "D"),   # ▓ dark shade
    (1.00, "#"),   # █ full block
]

# For half-block mode, we need the actual Unicode characters
HALF_TOP = "▀"
HALF_BOT = "▄"
FULL_BLK = "█"
EMPTY = " "


def load_and_resize(path, target_width=None):
    """Load image, convert to grayscale, optionally resize."""
    img = Image.open(path).convert("L")  # grayscale
    if target_width and target_width != img.width:
        ratio = target_width / img.width
        target_height = max(1, int(img.height * ratio))
        img = img.resize((target_width, target_height), Image.LANCZOS)
    return img


def brightness_at(img, x, y):
    """Get brightness 0.0 (black) to 1.0 (white) at pixel x,y."""
    if y >= img.height or x >= img.width:
        return 0.0
    return img.getpixel((x, y)) / 255.0


def to_shade_char(brightness):
    """Convert brightness to shade encoding character."""
    char = "."
    for threshold, c in SHADE_CHARS_FULL:
        if brightness >= threshold:
            char = c
    return char


def convert_full(img, invert=False):
    """Full mode: 1 pixel = 1 character cell with shade encoding."""
    rows = []
    for y in range(img.height):
        row = ""
        for x in range(img.width):
            b = brightness_at(img, x, y)
            if invert:
                b = 1.0 - b
            row += to_shade_char(b)
        rows.append(row)
    return rows


def convert_half(img, invert=False):
    """Half-block mode: 2 vertical pixels per character cell.

    Each output row encodes two image rows. Uses ▀ ▄ █ and space.
    Since this is monochrome (green on black), we only need to know
    which halves are "on" (above threshold).

    For shade awareness, we use a threshold: brightness >= 0.25 = on.
    """
    threshold = 0.25
    rows = []
    # Process image rows in pairs
    for y in range(0, img.height, 2):
        row = ""
        for x in range(img.width):
            b_top = brightness_at(img, x, y)
            b_bot = brightness_at(img, x, y + 1) if y + 1 < img.height else 0.0
            if invert:
                b_top = 1.0 - b_top
                b_bot = 1.0 - b_bot
            top_on = b_top >= threshold
            bot_on = b_bot >= threshold
            if top_on and bot_on:
                row += FULL_BLK
            elif top_on and not bot_on:
                row += HALF_TOP
            elif not top_on and bot_on:
                row += HALF_BOT
            else:
                row += EMPTY
        rows.append(row)
    return rows


def convert_half_shaded(img, invert=False):
    """Half-block mode with shade levels.

    Instead of binary on/off, we pick from multiple shade characters
    based on the average brightness of the two pixels in a cell.
    This gives better visual fidelity than pure half-blocks.

    When both pixels are similar brightness → use a shade char for full cell.
    When they differ significantly → use half-block chars.
    """
    threshold = 0.20
    rows = []
    for y in range(0, img.height, 2):
        row = ""
        for x in range(img.width):
            b_top = brightness_at(img, x, y)
            b_bot = brightness_at(img, x, y + 1) if y + 1 < img.height else 0.0
            if invert:
                b_top = 1.0 - b_top
                b_bot = 1.0 - b_bot
            top_on = b_top >= threshold
            bot_on = b_bot >= threshold
            if top_on and bot_on:
                # Both on — use shade character based on average brightness
                avg = (b_top + b_bot) / 2.0
                row += to_shade_char(avg)
            elif top_on and not bot_on:
                row += HALF_TOP
            elif not top_on and bot_on:
                row += HALF_BOT
            else:
                row += " "
        rows.append(row)
    return rows


def trim_transparent(rows, empty_char=None):
    """Remove leading/trailing empty columns and rows."""
    if not rows:
        return rows

    # Determine which characters count as empty
    empty_chars = {" ", "."}

    # Trim empty rows from top and bottom
    while rows and all(c in empty_chars for c in rows[0]):
        rows = rows[1:]
    while rows and all(c in empty_chars for c in rows[-1]):
        rows = rows[:-1]

    if not rows:
        return rows

    # Find leftmost and rightmost non-empty columns
    min_col = min(
        next((i for i, c in enumerate(row) if c not in empty_chars), len(row))
        for row in rows
    )
    max_col = max(
        next((i for i, c in enumerate(reversed(row)) if c not in empty_chars), len(row))
        for row in rows
    )
    max_col = max(len(row) for row in rows) - max_col

    # Trim columns
    rows = [row[min_col:max_col] for row in rows]
    return rows


def format_lua_sprite(rows, threshold=0, indent="\t\t"):
    """Format rows as a Lua sprite table entry."""
    lines = []
    lines.append(f"{indent[:-1]}" + "{")
    lines.append(f"{indent}threshold = {threshold},")
    lines.append(f"{indent}sprite = " + "{")
    for row in rows:
        lines.append(f'{indent}\t"{row}",')
    lines.append(f"{indent}" + "},")
    lines.append(f"{indent[:-1]}" + "},")
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(
        description="Convert images to WordGrinder terminal sprites"
    )
    parser.add_argument("image", help="Input image file (PNG, etc.)")
    parser.add_argument(
        "--mode",
        choices=["full", "half", "half-shaded"],
        default="full",
        help="Output mode: full (1:1), half (2 vert pixels/cell), "
             "half-shaded (half-block with shade levels)",
    )
    parser.add_argument(
        "--threshold",
        type=int,
        default=0,
        help="Word count threshold for this evolution stage",
    )
    parser.add_argument(
        "--width",
        type=int,
        default=None,
        help="Target width in characters (resizes image proportionally)",
    )
    parser.add_argument(
        "--invert",
        action="store_true",
        help="Invert brightness (use if subject is dark on light background)",
    )
    parser.add_argument(
        "--trim",
        action="store_true",
        default=True,
        help="Trim transparent/empty borders (default: true)",
    )
    parser.add_argument(
        "--no-trim",
        action="store_true",
        help="Don't trim transparent/empty borders",
    )

    args = parser.parse_args()

    img = load_and_resize(args.image, args.width)
    print(f"-- Source: {args.image} ({img.width}x{img.height}px)", file=sys.stderr)
    print(f"-- Mode: {args.mode}", file=sys.stderr)

    if args.mode == "full":
        rows = convert_full(img, args.invert)
    elif args.mode == "half":
        rows = convert_half(img, args.invert)
    elif args.mode == "half-shaded":
        rows = convert_half_shaded(img, args.invert)

    if args.trim and not args.no_trim:
        rows = trim_transparent(rows)

    out_height = len(rows)
    out_width = max(len(r) for r in rows) if rows else 0
    print(f"-- Output: {out_width}x{out_height} characters", file=sys.stderr)

    print(format_lua_sprite(rows, args.threshold))


if __name__ == "__main__":
    main()
