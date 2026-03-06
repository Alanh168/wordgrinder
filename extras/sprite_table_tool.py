#!/usr/bin/env python3
"""
Sprite table utility for WordGrinder Lua sprites.

Features:
  - List sprite/sprite_small tables found in a Lua source file.
  - Report dimensions (height, min/max row width).
  - Generate nearest-neighbor scaled Lua rows (default 2x).

This is intended for the existing palette-encoded sprites in
src/lua/addons/statistics.lua, but works with similar Lua blocks:

    threshold = <number>,
    sprite = {
        ".....",
        "..OO.",
    },
"""

import argparse
import re
import sys
from dataclasses import dataclass
from typing import List, Optional


THRESHOLD_RE = re.compile(r"^\s*threshold\s*=\s*[-]?\d+")
FIELD_RE = re.compile(r"^\s*(sprite|sprite_small)\s*=\s*{\s*$")
ROW_RE = re.compile(r'^\s*"([^"]*)",\s*$')
TABLE_END_RE = re.compile(r"^\s*},\s*$")


@dataclass
class SpriteBlock:
    stage: int
    field: str
    start_line: int
    end_line: int
    rows: List[str]


def scan_blocks(path: str) -> List[SpriteBlock]:
    with open(path, "r", encoding="utf-8") as fp:
        lines = fp.readlines()

    blocks: List[SpriteBlock] = []
    stage = 0
    collecting = False
    field = ""
    start_line = 0
    rows: List[str] = []

    for lineno, raw in enumerate(lines, start=1):
        if THRESHOLD_RE.match(raw):
            stage += 1

        if not collecting:
            m = FIELD_RE.match(raw)
            if m:
                collecting = True
                field = m.group(1)
                start_line = lineno
                rows = []
            continue

        if TABLE_END_RE.match(raw):
            blocks.append(
                SpriteBlock(
                    stage=stage,
                    field=field,
                    start_line=start_line,
                    end_line=lineno,
                    rows=rows,
                )
            )
            collecting = False
            field = ""
            start_line = 0
            rows = []
            continue

        rm = ROW_RE.match(raw)
        if rm:
            rows.append(rm.group(1))

    return blocks


def row_width_stats(rows: List[str]) -> tuple[int, int]:
    if not rows:
        return 0, 0
    widths = [len(r) for r in rows]
    return min(widths), max(widths)


def scale_rows(rows: List[str], factor: int, pad_to_rect: bool) -> List[str]:
    if factor < 1:
        raise ValueError("scale factor must be >= 1")
    if not rows:
        return []

    if pad_to_rect:
        maxw = max(len(r) for r in rows)
        rows = [r + ("." * (maxw - len(r))) for r in rows]

    out: List[str] = []
    for row in rows:
        scaled_row = "".join(ch * factor for ch in row)
        for _ in range(factor):
            out.append(scaled_row)
    return out


def find_block(
    blocks: List[SpriteBlock],
    stage: Optional[int],
    field: Optional[str],
    block_index: Optional[int],
) -> SpriteBlock:
    if block_index is not None:
        if block_index < 1 or block_index > len(blocks):
            raise ValueError(f"block index out of range: {block_index}")
        return blocks[block_index - 1]

    if stage is None or field is None:
        raise ValueError("choose either --block N or both --stage and --field")

    for block in blocks:
        if block.stage == stage and block.field == field:
            return block
    raise ValueError(f"no block found for stage={stage} field={field}")


def print_block_summary(index: int, block: SpriteBlock) -> None:
    minw, maxw = row_width_stats(block.rows)
    print(
        f"{index:2d}. stage={block.stage:<2} field={block.field:<11} "
        f"lines={block.start_line}-{block.end_line:<4} "
        f"height={len(block.rows):<2} width={minw}-{maxw}"
    )


def print_lua_rows(rows: List[str]) -> None:
    print("{")
    for row in rows:
        print(f'    "{row}",')
    print("}")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Inspect and scale Lua sprite tables")
    parser.add_argument("--file", required=True, help="Lua file containing sprite tables")
    parser.add_argument(
        "--list",
        action="store_true",
        help="List all detected sprite and sprite_small blocks",
    )
    parser.add_argument(
        "--stage",
        type=int,
        help="1-based stage number (from threshold entries)",
    )
    parser.add_argument(
        "--field",
        choices=["sprite", "sprite_small"],
        help="Sprite field to inspect",
    )
    parser.add_argument(
        "--block",
        type=int,
        help="1-based block index from --list output",
    )
    parser.add_argument(
        "--scale",
        type=int,
        default=2,
        help="Nearest-neighbor scale factor (default: 2)",
    )
    parser.add_argument(
        "--pad",
        action="store_true",
        help="Pad ragged rows with '.' before scaling",
    )
    parser.add_argument(
        "--print-original",
        action="store_true",
        help="Print the selected original Lua rows",
    )
    parser.add_argument(
        "--print-scaled",
        action="store_true",
        help="Print the scaled Lua rows",
    )
    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()

    blocks = scan_blocks(args.file)
    if not blocks:
        print(f"No sprite blocks found in {args.file}", file=sys.stderr)
        return 1

    if args.list:
        print(f"Found {len(blocks)} sprite blocks in {args.file}")
        for i, block in enumerate(blocks, start=1):
            print_block_summary(i, block)
        if not (args.block or args.stage or args.field):
            return 0

    try:
        block = find_block(blocks, args.stage, args.field, args.block)
    except ValueError as e:
        print(str(e), file=sys.stderr)
        return 1

    minw, maxw = row_width_stats(block.rows)
    print(
        f"Selected: stage={block.stage} field={block.field} "
        f"lines={block.start_line}-{block.end_line}"
    )
    print(f"Original: height={len(block.rows)} width={minw}-{maxw}")

    scaled = scale_rows(block.rows, args.scale, args.pad)
    sminw, smaxw = row_width_stats(scaled)
    print(
        f"Scaled x{args.scale}: height={len(scaled)} width={sminw}-{smaxw} "
        f"(pad={'yes' if args.pad else 'no'})"
    )

    if args.print_original:
        print("\n-- Original rows")
        print_lua_rows(block.rows)

    if args.print_scaled:
        print(f"\n-- Scaled rows (x{args.scale})")
        print_lua_rows(scaled)

    if not args.print_original and not args.print_scaled:
        print("\nUse --print-original and/or --print-scaled to output Lua row tables.")

    return 0


if __name__ == "__main__":
    sys.exit(main())
