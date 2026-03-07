#!/usr/bin/env python3
"""
Generate review sprite variants from candidate PNGs.

Default workflow:
  - Read input sprites from extras/sprites/candidates
  - Use the sibling image_to_pixel_art_wasm project's pixelate-cli
  - Write square-padded outputs into:
      extras/sprites/generated/8x8
      extras/sprites/generated/16x16
      extras/sprites/generated/32x32
      extras/sprites/generated/48x48
      extras/sprites/generated/64x64
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Iterable, List, Sequence

from PIL import Image


SCRIPT_DIR = Path(__file__).resolve().parent
WORDGRINDER_ROOT = SCRIPT_DIR.parent
WORKSPACE_ROOT = WORDGRINDER_ROOT.parent
SPRITES_ROOT = WORDGRINDER_ROOT / "extras" / "sprites"
DEFAULT_INPUT_DIR = SPRITES_ROOT / "candidates"
DEFAULT_GENERATED_DIR = SPRITES_ROOT / "generated"
DEFAULT_SIZES = (8, 16, 32, 48, 64)
PIXELATE_REPO = WORKSPACE_ROOT / "image_to_pixel_art_wasm"
PIXELATE_BIN = PIXELATE_REPO / "target" / "release" / "pixelate-cli"


def parse_sizes(raw: str) -> List[int]:
    sizes: List[int] = []
    seen = set()
    for part in raw.split(","):
        value = part.strip()
        if not value:
            continue
        try:
            size = int(value)
        except ValueError as exc:
            raise argparse.ArgumentTypeError(f"invalid size '{value}'") from exc
        if size < 1:
            raise argparse.ArgumentTypeError("sizes must be positive integers")
        if size not in seen:
            sizes.append(size)
            seen.add(size)
    if not sizes:
        raise argparse.ArgumentTypeError("at least one size is required")
    return sizes


def find_candidate_pngs(input_dir: Path) -> List[Path]:
    files = [p for p in input_dir.iterdir() if p.is_file() and p.suffix.lower() == ".png"]
    files.sort(key=lambda p: p.name.lower())
    return files


def resolve_inputs(input_dir: Path, requested: Sequence[str]) -> List[Path]:
    if not requested:
        return find_candidate_pngs(input_dir)

    resolved: List[Path] = []
    for item in requested:
        raw = Path(item).expanduser()
        if raw.is_absolute():
            path = raw
        else:
            path = input_dir / raw
            if not path.exists() and raw.suffix == "":
                alt = input_dir / f"{raw.name}.png"
                if alt.exists():
                    path = alt
        if not path.exists() or not path.is_file():
            raise FileNotFoundError(f"Candidate sprite not found: {item}")
        if path.suffix.lower() != ".png":
            raise ValueError(f"Candidate sprite is not a PNG: {path}")
        resolved.append(path.resolve())
    return resolved


def detect_pixelate_command(explicit_path: str | None) -> List[str]:
    if explicit_path:
        executable = Path(explicit_path).expanduser()
        if not executable.is_absolute():
            executable = (Path.cwd() / executable).resolve()
        if not executable.exists():
            raise FileNotFoundError(f"pixelate-cli not found: {executable}")
        return [str(executable)]

    if PIXELATE_BIN.exists():
        return [str(PIXELATE_BIN)]

    cargo = shutil.which("cargo")
    if cargo:
        return [
            cargo,
            "run",
            "--release",
            "--features",
            "native-bin",
            "--bin",
            "pixelate-cli",
            "--",
        ]

    raise FileNotFoundError(
        "Could not find pixelate-cli. Build image_to_pixel_art_wasm/target/release/pixelate-cli "
        "or install cargo."
    )


def build_palette_args(
    input_path: Path,
    palette: str | None,
    palette_source: str,
) -> List[str]:
    if palette:
        return ["--palette", palette]

    if palette_source == "none":
        return []

    if palette_source == "self":
        return ["--fix-palette", str(input_path)]

    ref = Path(palette_source).expanduser()
    if not ref.is_absolute():
        ref = (Path.cwd() / ref).resolve()
    if not ref.exists():
        raise FileNotFoundError(f"Palette reference image not found: {ref}")
    return ["--fix-palette", str(ref)]


def run_pixelate(
    command_prefix: Sequence[str],
    repo_dir: Path,
    input_path: Path,
    output_size: int,
    output_dir: Path,
    n_colors: int,
    relative_scale: float,
    palette_args: Sequence[str],
    no_downscale: bool,
) -> Path:
    cmd = list(command_prefix)
    cmd.extend(
        [
            str(input_path),
            "--n-colors",
            str(n_colors),
            "--relative-scale",
            str(relative_scale),
            "--output-size",
            str(output_size),
            "--out-dir",
            str(output_dir),
        ]
    )
    cmd.extend(palette_args)
    if no_downscale:
        cmd.append("--no-downscale")

    result = subprocess.run(
        cmd,
        cwd=repo_dir,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        details = result.stderr.strip() or result.stdout.strip() or "pixelate-cli failed"
        raise RuntimeError(details)

    output_path = output_dir / f"{input_path.stem}.png"
    if not output_path.exists():
        raise FileNotFoundError(f"Expected generated file was not created: {output_path}")
    return output_path


def pad_to_square(source_path: Path, dest_path: Path, size: int) -> tuple[int, int]:
    with Image.open(source_path).convert("RGBA") as image:
        src_w, src_h = image.size
        if src_w > size or src_h > size:
            raise ValueError(
                f"Generated sprite {source_path} is larger than target canvas {size}x{size}"
            )
        canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        offset_x = (size - src_w) // 2
        offset_y = (size - src_h) // 2
        canvas.paste(image, (offset_x, offset_y), image)
        canvas.save(dest_path)
    return src_w, src_h


def copy_without_padding(source_path: Path, dest_path: Path) -> tuple[int, int]:
    with Image.open(source_path) as image:
        src_size = image.size
    shutil.copy2(source_path, dest_path)
    return src_size


def iter_target_dirs(base_dir: Path, sizes: Iterable[int]) -> Iterable[Path]:
    for size in sizes:
        yield base_dir / f"{size}x{size}"


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Generate review sprite variants from candidate PNGs")
    parser.add_argument(
        "inputs",
        nargs="*",
        help="Optional candidate PNG filenames or paths. Defaults to all PNGs in the candidate folder.",
    )
    parser.add_argument(
        "--input-dir",
        default=str(DEFAULT_INPUT_DIR),
        help=f"Candidate PNG directory (default: {DEFAULT_INPUT_DIR})",
    )
    parser.add_argument(
        "--generated-dir",
        default=str(DEFAULT_GENERATED_DIR),
        help=f"Generated output root (default: {DEFAULT_GENERATED_DIR})",
    )
    parser.add_argument(
        "--sizes",
        default="8,16,32,48,64",
        help="Comma-separated square canvas sizes to generate (default: 8,16,32,48,64)",
    )
    parser.add_argument(
        "--n-colors",
        type=int,
        default=16,
        help="Number of colors for pixelate-cli when no custom palette is supplied (default: 16)",
    )
    parser.add_argument(
        "--relative-scale",
        type=float,
        default=1.0,
        help="pixelate-cli relative scale value (default: 1.0)",
    )
    parser.add_argument(
        "--palette",
        help="Comma-separated hex palette to pass directly to pixelate-cli",
    )
    parser.add_argument(
        "--palette-source",
        default="self",
        help="Palette source image: 'self' (default), 'none', or a path to a reference image",
    )
    parser.add_argument(
        "--pixelate-cli",
        help="Path to a prebuilt pixelate-cli executable. Defaults to auto-detect.",
    )
    parser.add_argument(
        "--no-downscale",
        action="store_true",
        help="Pass through --no-downscale to pixelate-cli",
    )
    parser.add_argument(
        "--no-pad",
        action="store_true",
        help="Do not center-pad outputs to square canvases after generation",
    )
    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()

    if args.n_colors < 1:
        print("--n-colors must be >= 1", file=sys.stderr)
        return 1
    if args.relative_scale <= 0:
        print("--relative-scale must be > 0", file=sys.stderr)
        return 1

    input_dir = Path(args.input_dir).expanduser().resolve()
    generated_dir = Path(args.generated_dir).expanduser().resolve()
    sizes = parse_sizes(args.sizes)

    if not input_dir.exists() or not input_dir.is_dir():
        print(f"Input directory does not exist: {input_dir}", file=sys.stderr)
        return 1

    try:
        inputs = resolve_inputs(input_dir, args.inputs)
    except (FileNotFoundError, ValueError) as exc:
        print(str(exc), file=sys.stderr)
        return 1

    if not inputs:
        print(
            f"No PNG files found in {input_dir}. Drop candidate sprites there first.",
            file=sys.stderr,
        )
        return 1

    for path in iter_target_dirs(generated_dir, sizes):
        path.mkdir(parents=True, exist_ok=True)

    try:
        command_prefix = detect_pixelate_command(args.pixelate_cli)
    except FileNotFoundError as exc:
        print(str(exc), file=sys.stderr)
        return 1

    print("Using pixelate tool:", " ".join(command_prefix))

    try:
        with tempfile.TemporaryDirectory(prefix="wg-sprite-gen-") as temp_dir_raw:
            temp_dir = Path(temp_dir_raw)
            for input_path in inputs:
                palette_args = build_palette_args(input_path, args.palette, args.palette_source)
                for size in sizes:
                    temp_out_dir = temp_dir / f"{input_path.stem}-{size}"
                    temp_out_dir.mkdir(parents=True, exist_ok=True)

                    generated_png = run_pixelate(
                        command_prefix,
                        PIXELATE_REPO,
                        input_path,
                        size,
                        temp_out_dir,
                        args.n_colors,
                        args.relative_scale,
                        palette_args,
                        args.no_downscale,
                    )

                    dest_dir = generated_dir / f"{size}x{size}"
                    dest_path = dest_dir / f"{input_path.stem}.png"
                    if args.no_pad:
                        src_w, src_h = copy_without_padding(generated_png, dest_path)
                        final_label = f"{src_w}x{src_h}"
                    else:
                        src_w, src_h = pad_to_square(generated_png, dest_path, size)
                        final_label = f"{size}x{size}"

                    print(
                        f"{input_path.name} -> {dest_path.relative_to(generated_dir.parent)} "
                        f"(pixelated {src_w}x{src_h}, saved {final_label})"
                    )
    except (FileNotFoundError, RuntimeError, ValueError) as exc:
        print(str(exc), file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
