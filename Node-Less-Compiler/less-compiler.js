#!/usr/bin/env node

import CleanCSS from "clean-css";
import less from "less";
import fs from "node:fs/promises";
import path from "node:path";

const manifestName = ".less-compiler-manifest.json";
const ignoredDirectories = new Set(["node_modules", ".git"]);

function printHelp() {
    console.log(`LESS Compiler

Usage:
  node less-compiler.js --src <directory> --dest <directory> [options]
  node less-compiler.js <source-directory> <destination-directory> [options]

Options:
  --src <directory>       Directory containing .less files
  --dest <directory>      Directory for generated .css and .min.css files
  --no-minify             Generate only .css files
  --include-partials      Also compile .less files whose names start with _
  --clean                 Remove stale files from previous runs of this tool
  -h, --help              Show this help

Paths are resolved relative to the current working directory.
Without --clean, existing unrelated files are never deleted.
`);
}

function parseArgs(args) {
    const options = { src: null, dest: null, minify: true, includePartials: false, clean: false };
    const positional = [];

    for (let i = 0; i < args.length; i++) {
        const arg = args[i];
        if (arg === "-h" || arg === "--help") {
            return { help: true };
        }
        if (arg === "--no-minify") {
            options.minify = false;
        } else if (arg === "--include-partials") {
            options.includePartials = true;
        } else if (arg === "--clean") {
            options.clean = true;
        } else if (arg === "--src" || arg === "--dest") {
            const value = args[++i];
            if (!value || value.startsWith("--")) {
                throw new Error(`Missing directory after ${arg}`);
            }
            options[arg.slice(2)] = value;
        } else if (arg.startsWith("-")) {
            throw new Error(`Unknown option: ${arg}`);
        } else {
            positional.push(arg);
        }
    }

    if (positional.length > 2 || (positional.length && (options.src || options.dest))) {
        throw new Error("Use either two positional paths or --src and --dest.");
    }
    options.src ??= positional[0];
    options.dest ??= positional[1];
    if (!options.src || !options.dest) {
        throw new Error("Source and destination directories are required. See --help.");
    }
    options.src = path.resolve(options.src);
    options.dest = path.resolve(options.dest);
    if (options.src === options.dest) {
        throw new Error("Source and destination must be different directories.");
    }
    return options;
}

async function* findLessFiles(directory, includePartials) {
    const entries = await fs.readdir(directory, { withFileTypes: true });
    entries.sort((a, b) => a.name.localeCompare(b.name));

    for (const entry of entries) {
        const fullPath = path.join(directory, entry.name);
        if (entry.isDirectory()) {
            if (!ignoredDirectories.has(entry.name)) {
                yield* findLessFiles(fullPath, includePartials);
            }
        } else if (entry.isFile() && entry.name.toLowerCase().endsWith(".less")) {
            if (includePartials || !entry.name.startsWith("_")) {
                yield fullPath;
            }
        }
    }
}

function isWithinDirectory(directory, filename) {
    const relative = path.relative(directory, filename);
    return relative !== "" && relative !== ".." && !relative.startsWith(`..${path.sep}`) && !path.isAbsolute(relative);
}

async function readManifest(manifestPath, destDir) {
    try {
        const data = JSON.parse(await fs.readFile(manifestPath, "utf8"));
        if (!Array.isArray(data.files) || data.version !== 1) {
            throw new Error("Invalid manifest format");
        }
        return new Set(data.files.filter((value) => typeof value === "string" && isWithinDirectory(destDir, path.resolve(destDir, value))));
    } catch (error) {
        if (error.code === "ENOENT") {
            return new Set();
        }
        throw new Error(`Cannot read manifest ${manifestPath}: ${error.message}`);
    }
}

async function removeEmptyParentDirectories(filename, destination) {
    let directory = path.dirname(filename);
    while (isWithinDirectory(destination, directory)) {
        if ((await fs.readdir(directory)).length > 0) {
            break;
        }
        await fs.rmdir(directory);
        directory = path.dirname(directory);
    }
}

async function run(options) {
    const sourceStats = await fs.stat(options.src);
    if (!sourceStats.isDirectory()) {
        throw new Error(`Source is not a directory: ${options.src}`);
    }
    await fs.mkdir(options.dest, { recursive: true });

    const manifestPath = path.join(options.dest, manifestName);
    const previousFiles = await readManifest(manifestPath, options.dest);
    const generatedFiles = new Set();
    const minifier = new CleanCSS();
    let fileCount = 0;

    for await (const filename of findLessFiles(options.src, options.includePartials)) {
        const relative = path.relative(options.src, filename).replace(/\.less$/i, ".css");
        const cssFile = path.join(options.dest, relative);
        const minFile = cssFile.replace(/\.css$/i, ".min.css");
        const source = await fs.readFile(filename, "utf8");

        console.log(`Compiling: ${path.relative(options.src, filename)}`);
        const result = await less.render(source, { filename });
        await fs.mkdir(path.dirname(cssFile), { recursive: true });
        await fs.writeFile(cssFile, result.css, "utf8");
        generatedFiles.add(relative);

        if (options.minify) {
            const minified = minifier.minify(result.css);
            if (minified.errors.length > 0) {
                throw new Error(`${filename}: ${minified.errors.join("; ")}`);
            }
            await fs.writeFile(minFile, minified.styles, "utf8");
            generatedFiles.add(path.relative(options.dest, minFile));
        }
        fileCount++;
    }

    if (options.clean) {
        for (const relative of previousFiles) {
            if (generatedFiles.has(relative)) {
                continue;
            }
            const filename = path.resolve(options.dest, relative);
            if (!isWithinDirectory(options.dest, filename)) {
                continue;
            }
            try {
                await fs.unlink(filename);
                console.log(`Removed stale file: ${relative}`);
                await removeEmptyParentDirectories(filename, options.dest);
            } catch (error) {
                if (error.code !== "ENOENT") {
                    throw error;
                }
            }
        }
    }

    const trackedFiles = options.clean ? generatedFiles : new Set([...previousFiles, ...generatedFiles]);
    await fs.writeFile(manifestPath, JSON.stringify({ version: 1, files: [...trackedFiles].sort() }, null, 2) + "\n");
    console.log(`✅ Completed: ${fileCount} LESS file(s) compiled.`);
}

try {
    const options = parseArgs(process.argv.slice(2));
    if (options.help) {
        printHelp();
    } else {
        await run(options);
    }
} catch (error) {
    console.error(`❌ ${error.message}`);
    process.exitCode = 1;
}
