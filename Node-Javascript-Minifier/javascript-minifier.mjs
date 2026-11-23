#!/usr/bin/env node

import { build } from "esbuild";
import fs from "node:fs/promises";
import path from "node:path";

const manifestName = ".javascript-minifier-manifest.json";
const ignoredDirectories = new Set([".git", "node_modules"]);

function printHelp() {
    console.log(`JavaScript Minifier

Usage:
  node javascript-minifier.mjs --src <directory> --dest <directory> [options]
  node javascript-minifier.mjs <source-directory> <destination-directory> [options]

Options:
  --src <directory>    Source directory containing JavaScript files
  --dest <directory>   Destination directory for .min.js files
  --target <version>   ECMAScript target for esbuild (default: es2017)
  --clean              Delete stale output files tracked by this tool
  -h, --help           Show this help

Paths are relative to the current working directory unless absolute.
Only .js files are processed; .min.js files are skipped.
`);
}

function parseArgs(args) {
    const options = { src: null, dest: null, target: "es2017", clean: false };
    const positional = [];

    for (let i = 0; i < args.length; i++) {
        const arg = args[i];
        if (arg === "-h" || arg === "--help") {
            return { help: true };
        }
        if (arg === "--clean") {
            options.clean = true;
        } else if (["--src", "--dest", "--target"].includes(arg)) {
            const value = args[++i];
            if (!value || value.startsWith("--")) {
                throw new Error(`Missing value after ${arg}`);
            }
            options[arg.slice(2)] = value;
        } else if (arg.startsWith("-")) {
            throw new Error(`Unknown option: ${arg}`);
        } else {
            positional.push(arg);
        }
    }

    if (positional.length > 2 || (positional.length > 0 && (options.src || options.dest))) {
        throw new Error("Use either two positional paths or --src and --dest.");
    }
    options.src ??= positional[0];
    options.dest ??= positional[1];
    if (!options.src || !options.dest) {
        throw new Error("Source and destination directories are required. See --help.");
    }
    options.src = path.resolve(options.src);
    options.dest = path.resolve(options.dest);
    if (options.src === options.dest || isWithinDirectory(options.src, options.dest)) {
        throw new Error("Destination must be outside the source directory.");
    }
    return options;
}

function isWithinDirectory(directory, filename) {
    const relative = path.relative(directory, filename);
    return relative !== "" && relative !== ".." && !relative.startsWith(`..${path.sep}`) && !path.isAbsolute(relative);
}

async function* findSourceFiles(directory) {
    const entries = await fs.readdir(directory, { withFileTypes: true });
    entries.sort((a, b) => a.name.localeCompare(b.name));

    for (const entry of entries) {
        const filename = path.join(directory, entry.name);
        if (entry.isDirectory() && !ignoredDirectories.has(entry.name)) {
            yield* findSourceFiles(filename);
        } else if (entry.isFile() && entry.name.endsWith(".js") && !entry.name.endsWith(".min.js")) {
            yield filename;
        }
    }
}

async function readManifest(filename, destination) {
    try {
        const data = JSON.parse(await fs.readFile(filename, "utf8"));
        if (data.version !== 1 || !Array.isArray(data.files) || !data.files.every((value) => typeof value === "string" && isWithinDirectory(destination, path.resolve(destination, value)))) {
            throw new Error("Invalid manifest format");
        }
        return new Set(data.files);
    } catch (error) {
        if (error.code === "ENOENT") {
            return new Set();
        }
        throw new Error(`Cannot read manifest: ${error.message}`);
    }
}

async function removeEmptyParents(filename, destination) {
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
    const sourceStat = await fs.stat(options.src);
    if (!sourceStat.isDirectory()) {
        throw new Error(`Source is not a directory: ${options.src}`);
    }
    await fs.mkdir(options.dest, { recursive: true });

    const manifestPath = path.join(options.dest, manifestName);
    const previousFiles = await readManifest(manifestPath, options.dest);
    const generatedFiles = new Set();
    let count = 0;

    for await (const filename of findSourceFiles(options.src)) {
        const relative = path.relative(options.src, filename).replace(/\.js$/, ".min.js");
        const destination = path.join(options.dest, relative);
        await fs.mkdir(path.dirname(destination), { recursive: true });
        console.log(`Minifying: ${path.relative(options.src, filename)} -> ${relative}`);

        // Preserve the original script's behavior: minify without bundling.
        await build({
            entryPoints: [filename],
            bundle: false,
            minify: true,
            sourcemap: false,
            target: options.target,
            outfile: destination,
            logLevel: "silent",
        });
        generatedFiles.add(relative);
        count++;
    }

    if (options.clean) {
        for (const relative of previousFiles) {
            if (generatedFiles.has(relative)) {
                continue;
            }
            const filename = path.resolve(options.dest, relative);
            try {
                await fs.unlink(filename);
                console.log(`Removed stale file: ${relative}`);
                await removeEmptyParents(filename, options.dest);
            } catch (error) {
                if (error.code !== "ENOENT") {
                    throw error;
                }
            }
        }
    }

    // Track both current and still-existing older files when cleanup was not requested.
    const trackedFiles = options.clean ? generatedFiles : new Set([...previousFiles, ...generatedFiles]);
    await fs.writeFile(
        manifestPath,
        JSON.stringify(
            {
                version: 1,
                files: [...trackedFiles].sort(),
            },
            null,
            2,
        ) + "\n",
        "utf8",
    );
    console.log(`Done: ${count} file(s) minified.`);
}

try {
    const options = parseArgs(process.argv.slice(2));
    if (options.help) {
        printHelp();
    } else {
        await run(options);
    }
} catch (error) {
    console.error(`Error: ${error.message}`);
    process.exitCode = 1;
}
