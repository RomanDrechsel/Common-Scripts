from __future__ import annotations

import argparse
from pathlib import Path
from fontTools import subset
from fontTools.ttLib import TTLibError

OUTPUT_FORMATS = {
    ".woff2": "woff2",
    ".woff": "woff",
    ".ttf": None,
    ".otf": None,
}

BASE_CODEPOINTS = {
    *range(0x20, 0x7F),
    0x09,
    0x0A,
    0x0D,
}


def read_text_file(path: Path) -> str | None:
    encodings = (
        "utf-8",
        "utf-8-sig",
        "utf-16",
        "cp1252",
    )

    for encoding in encodings:
        try:
            return path.read_text(encoding=encoding)
        except UnicodeDecodeError:
            continue
        except OSError as exc:
            print(f"Cannot read {path}: {exc}")
            return None

    return None


def collect_codepoints(base_directory: Path) -> set[int]:
    codepoints = set(BASE_CODEPOINTS)

    for path in base_directory.rglob("*"):
        if not path.is_file():
            continue

        text = read_text_file(path)

        if text is None:
            print(f"Skipped: {path}")
            continue

        file_codepoints = {ord(char) for char in text}
        codepoints.update(file_codepoints)

        print(f"{path}: " f"{len(file_codepoints)} unique codepoints")

    return codepoints


def create_subset(
    font_path: Path,
    output_path: Path,
    codepoints: set[int],
    compact: bool,
) -> None:
    options = subset.Options()

    extension = output_path.suffix.lower()
    if extension not in OUTPUT_FORMATS:
        raise ValueError(f"Unsupported output format: {extension}")
    options.flavor = OUTPUT_FORMATS[extension]

    if compact:
        configure_compact_options(options)
    else:
        configure_standard_options(options)

    font = subset.load_font(
        str(font_path),
        options,
        lazy=False,
    )

    # Subsetting preserves the original outline technology.
    if extension == ".ttf" and "glyf" not in font:
        raise ValueError("TTF output requires a TrueType-based source font.")
    if extension == ".otf" and not ("CFF " in font or "CFF2" in font):
        raise ValueError("OTF output requires a CFF-based source font.")
    # Prevent inherited web-font compression for uncompressed output.
    font.flavor = options.flavor

    subsetter = subset.Subsetter(options=options)
    subsetter.populate(unicodes=codepoints)
    subsetter.subset(font)

    subset.save_font(
        font,
        str(output_path),
        options,
    )


def configure_standard_options(
    options: subset.Options,
) -> None:
    options.name_IDs = ["*"]
    options.name_legacy = True
    options.name_languages = ["*"]
    options.layout_features = ["*"]


def configure_compact_options(
    options: subset.Options,
) -> None:
    # Keep only essential naming information.
    options.name_IDs = [
        1,  # Font Family
        2,  # Font Subfamily
        4,  # Full Font Name
        6,  # PostScript Name
    ]

    options.name_legacy = False
    options.name_languages = [0x0409]

    # Remove OpenType layout features.
    options.layout_features = []

    # Remove TrueType hinting data.
    options.hinting = False

    # Remove legacy kerning information.
    options.legacy_kern = False

    # Remove symbol cmap data.
    options.symbol_cmap = False

    # Remove glyph names.
    options.glyph_names = False

    # Remove tables that are not needed for this use case.
    additional_drop_tables = {
        "DSIG",
        "FFTM",
        "GDEF",
        "GPOS",
        "GSUB",
        "hdmx",
        "LTSH",
        "VDMX",
    }

    options.drop_tables = list(set(options.drop_tables) | additional_drop_tables)


def main() -> None:
    parser = argparse.ArgumentParser(
        description=(
            "Scan all files below a directory, collect used Unicode "
            "codepoints and create a font subset."
        )
    )

    parser.add_argument(
        "--compact",
        action="store_true",
        help=(
            "Create a more aggressively reduced font. "
            "Removes hinting, OpenType layout features, "
            "glyph names and unnecessary metadata."
        ),
    )

    parser.add_argument(
        "scan", type=Path, help="Directory to scan for all codepoints in files"
    )

    parser.add_argument(
        "font",
        type=Path,
        help="Source TTF or OTF font",
    )

    parser.add_argument(
        "output",
        type=Path,
        help="Output file (.woff2, .woff, .ttf, .otf)",
    )

    args = parser.parse_args()

    scan_path = args.scan.resolve()
    if not scan_path.is_dir():
        raise SystemExit(f"Scan directory does not exist: {scan_path}\n")

    font_path = args.font.resolve()
    if not font_path.is_file():
        raise SystemExit(f"Font does not exist: {font_path}\n")

    output_path = args.output.resolve()
    if output_path.suffix.lower() not in OUTPUT_FORMATS:
        parser.error("Output extension must be .woff2, .woff, .ttf or .otf")
    if output_path == font_path or (output_path.exists() and output_path.samefile(font_path)):
        parser.error("Output file must not overwrite the source font")
    output_path.parent.mkdir(
        parents=True,
        exist_ok=True,
    )

    mode = "compact" if args.compact else "standard"

    print(f"Base directory: {scan_path}")
    print(f"Source font:    {font_path}")
    print(f"Output font:    {output_path}")
    print(f"Mode:           {mode}")
    print()

    codepoints = collect_codepoints(scan_path)

    print()
    print(f"Collected codepoints: {len(codepoints)}")
    print()

    try:
        create_subset(
            font_path=font_path,
            output_path=output_path,
            codepoints=codepoints,
            compact=args.compact,
        )
    except (ValueError, OSError, ImportError, TTLibError) as exc:
        raise SystemExit(f"Cannot create font subset: {exc}") from exc

    original_size = font_path.stat().st_size
    subset_size = output_path.stat().st_size

    print(f"Original size: {original_size / 1024:.1f} KiB")
    print(f"Subset size:   {subset_size / 1024:.1f} KiB")

    if original_size:
        reduction = (1 - subset_size / original_size) * 100
        print(f"Reduction:     {reduction:.1f}%")


if __name__ == "__main__":
    main()
