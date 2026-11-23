# JavaScript Minifier

**🇬🇧 English** | [🇩🇪 Deutsch](README.de.md)

A reusable Node.js CLI tool for recursively minifying JavaScript files with **esbuild**. It turns `.js` files into `.min.js` files and preserves their relative directory structure. Source and destination paths are CLI arguments—there are no hard-coded project paths.

## Features

- Recursively process `.js` files in a source directory.
- Skip existing `.min.js` files and the `.git` and `node_modules` directories.
- Preserve relative subdirectories in the destination.
- Minify without bundling (`bundle: false`), just like the original script.
- Use ECMAScript **ES2017** as the default target, or customize it with `--target`.
- Optionally remove outdated outputs with `--clean` using a manifest of generated files.
- Show progress and return an exit code other than zero if something fails.

## Requirements

- Node.js 18 or newer
- npm

## Installation

Copy `javascript-minifier.mjs` and `package.json` into the same directory and run:

```bash
npm install
```

## Usage

Run the script from the directory of your choice:

```bash
node /path/to/javascript-minifier.mjs --src ./assets/javascript --dest ./public/js
```

Alternatively, pass the directories as positional arguments:

```bash
node /path/to/javascript-minifier.mjs ./assets/javascript ./public/js
```

**Relative paths are resolved against your current working directory**, not the script directory. Absolute paths work too.

### Options

| Option               | Description                                                       |
| -------------------- | ----------------------------------------------------------------- |
| `--src <directory>`  | Required source directory.                                        |
| `--dest <directory>` | Required destination directory (created automatically).           |
| `--target <version>` | ECMAScript target for esbuild (default: `es2017`; e.g. `es2020`). |
| `--clean`            | Remove outdated outputs previously tracked by this tool.          |
| `-h`, `--help`       | Show help.                                                        |

Specify directories either with `--src` and `--dest` **or** as two positional paths; do not mix the forms.

### Example

Source:

```text
assets/javascript/
├── main.js
├── main.min.js
└── admin/
    └── dashboard.js
```

Command:

```bash
node javascript-minifier.mjs --src assets/javascript --dest public/js
```

Generated files:

```text
public/js/
├── .javascript-minifier-manifest.json
├── main.min.js
└── admin/
    └── dashboard.min.js
```

`main.min.js` in the source directory is skipped.

## Cleanup and safety

By default, the script **does not delete** files. It writes a manifest named `.javascript-minifier-manifest.json` into the destination directory to track its generated outputs. To remove tracked outputs whose sources have since been removed, run:

```bash
node javascript-minifier.mjs --src assets/javascript --dest public/js --clean
```

`--clean` removes only paths recorded in a previous manifest and not generated during the current run. An overwritten file at a previously tracked path is **not** recognized as belonging to another tool; keep the destination dedicated to this minifier and do not edit its generated files manually. Files with the same names as the new outputs are overwritten even without `--clean`.

The destination must be outside the source directory. Symbolic-link directories are not traversed.

## Notes

- Only `.js` inputs are processed (not `.mjs`, `.cjs`, or TypeScript).
- The minifier does not bundle imports and does not create source maps.
- The tool requires Node.js and the `esbuild` dependency; it is not a standalone native executable.
- There is no watch mode.

## License and author

Copyright © 2026 **Roman Drechsel** — [roman-drechsel.de](https://roman-drechsel.de).

This project is licensed under the **GNU General Public License v3.0 (GPL-3.0-only)**.

You are free to use, modify, and distribute this software, including for commercial purposes, under the terms of the GNU GPL v3.0.

See the full license text in [`LICENSE`](LICENSE) or visit the [GNU GPL v3.0 website](https://www.gnu.org/licenses/gpl-3.0.en.html).

## AI-assisted development

These scripts and their documentation were created in part with the assistance of artificial intelligence (AI), including ChatGPT. AI-assisted code is not a guarantee of correctness. Review and test the scripts for your own use case, especially before relying on automated backups or restores.
