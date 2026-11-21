# Font Subset Creator

**🇬🇧 English** | [🇩🇪 Deutsch](README.de.md)

A Python script that recursively scans files in a directory, collects the Unicode codepoints used in those files and creates a reduced WOFF2, WOFF, TTF or OTF font from a TTF or OTF source font. Useful for websites, static text, source-code displays and other applications with a known character repertoire.

## Features

- Recursively scan all files, including files in nested directories.
- Collect unique Unicode codepoints and always include printable ASCII, tab, line feed and carriage return.
- Try UTF-8, UTF-8 with BOM, UTF-16 and Windows-1252 when reading files.
- Create WOFF2, WOFF, TTF or OTF fonts using FontTools.
- Choose between standard and aggressive compact subsetting.
- Automatically create missing output directories.
- Report per-file character counts, total codepoints, font sizes and percentage reduction.

## Requirements and installation

- Python 3.10 or newer (recommended)
- FontTools (Brotli required only for WOFF2 output)

Install the dependencies in a virtual environment:

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install 'fonttools[woff]'
```

Alternatively, on Arch Linux or Manjaro:

```bash
sudo pacman -S python-fonttools python-brotli
```

## Usage

```bash
python3 create_font_subset.py [--compact] <scan> <font> <output>
```

| Argument | Description |
| --- | --- |
| `scan` | Required directory to scan recursively. |
| `font` | Required path to the source TTF or OTF font. |
| `output` | Required output path; use `.woff2`, `.woff`, `.ttf` or `.otf`. |
| `--compact` | Optional aggressive reduction of font data. |
| `-h`, `--help` | Show command-line help. |

Relative paths are resolved against the current working directory. All three positional arguments are required.

### Output formats

The output extension selects the format automatically (case-insensitive).

| Extension | Supported source outlines |
| --- | --- |
| `.woff2` | TrueType or CFF; requires Brotli |
| `.woff` | TrueType or CFF |
| `.ttf` | TrueType |
| `.otf` | CFF or CFF2 |

Subsetting does not convert outline technologies. Unsupported extensions and incompatible TTF/OTF output are rejected. The source font cannot be overwritten.

```bash
python3 create_font_subset.py ./sourcecode ./fonts/JetBrainsMono.ttf ./fonts/subset.woff
python3 create_font_subset.py ./sourcecode ./fonts/JetBrainsMono.ttf ./fonts/subset.ttf
python3 create_font_subset.py ./sourcecode ./fonts/SourceCodePro-Regular.otf ./fonts/subset.otf
```

### Standard mode

```bash
python3 create_font_subset.py ./sourcecode ./fonts/JetBrainsMono.ttf ./public/fonts/JetBrainsMono-subset.woff2
```

### Compact mode

```bash
python3 create_font_subset.py --compact ./sourcecode ./fonts/JetBrainsMono.ttf ./public/fonts/JetBrainsMono-subset.woff2
```

## Subsetting modes

| Feature | Standard | Compact |
| --- | --- | --- |
| Character subsetting | Yes | Yes |
| Naming metadata | All name IDs and languages requested | Essential name IDs, English only |
| OpenType layout features | All features requested | Removed |
| Hinting | Default FontTools behavior | Removed |
| Legacy kerning, symbol cmap, glyph names | Default FontTools behavior | Disabled |
| Additional table removal | Default FontTools behavior | Includes GDEF, GPOS, GSUB and other tables |

Standard mode is the safer choice for general text. Compact mode targets small file sizes, especially for simple static text or source-code displays. It can affect ligatures, kerning, character positioning, complex-script shaping and rendering at small sizes.

## Using the generated font on a website

```css
@font-face {
    font-family: 'Code Subset';
    src: url('/fonts/JetBrainsMono-subset.woff2') format('woff2');
    font-display: swap;
}

.source-code {
    font-family: 'Code Subset', monospace;
}
```

Adjust the URL and font descriptors to match your actual font and deployment.

## Limitations and recommendations

- The script scans every file without extension filters or directory exclusions. Use a dedicated text-only input directory; binary files may be decoded as text and introduce unwanted characters.
- Undecodable or unreadable files are skipped. Check the console output for skipped files.
- The encoding fallback is heuristic, not automatic encoding detection.
- Only characters available in the source font can be included. The number of collected Unicode codepoints is not necessarily the number of output glyphs.
- Regenerate the subset when the input text changes; new characters may otherwise be missing.
- Keep source fonts and generated files outside the scan directory. The source font is protected against overwriting, but other existing output files may be overwritten.
- Size reduction depends on the font and the collected characters; a smaller file is not guaranteed.
- Check the source font's license before modifying, embedding or distributing it. Compact mode removes metadata that may include licensing information; retain any required notices separately.

## AI-assisted development

This script and its documentation were created in part with the assistance of artificial intelligence (AI), including ChatGPT. AI-assisted code is not a guarantee of correctness. Review and test the script for your own use case.
