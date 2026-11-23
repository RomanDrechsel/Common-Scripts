# Linux Scripts

A collection of useful scripts for Linux, automation,
backup and software development.

## Available scripts

| Script                                                               | Language                                                                                                                                          | Description                                                                                                                                                                                                                                                                                         |
| -------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [Font Subset](./Font-Subsets/)                                       | <img src="https://cdn.jsdelivr.net/gh/devicons/devicon@latest/icons/python/python-original.svg" width="24" alt="Python"> Python                   | Create optimized WOFF2, WOFF, TTF or OTF font subsets.<br /><br /> This script recursively scans files in a directory, collects the Unicode codepoints used in those files and creates a reduced font from a TTF or OTF source font.                                                                |
| [Large Thunderbird / Betterbird Backup](./Large-Thunderbird-Backup/) | <img src="https://cdn.jsdelivr.net/gh/devicons/devicon@latest/icons/bash/bash-original.svg" width="24" alt="Bash"> Bash                           | Backup and restore Thunderbird and Betterbird settings and e-mails, if the profile is larger than 2 GB.<br /><br /> Thunderbird / Betterbird can only im- and export profiles, that are smaller than 2 GB. This script creates a zip-achive from the profile, that can be copied into a new profile |
| [Node.js Javascript Minifier](./Node-Javascript-Minifier)            | <img src="https://cdn.jsdelivr.net/gh/devicons/devicon@latest/icons/javascript/javascript-original.svg" width="24" alt="Javascript" /> Javascript | A reusable Node.js CLI tool for recursively minifying JavaScript files with **esbuild**.                                                                                                                                                                                                            |
| [Node.js LESS Compiler](./Node-Less-Compiler)                        | <img src="https://cdn.jsdelivr.net/gh/devicons/devicon@latest/icons/javascript/javascript-original.svg" width="24" alt="Javascript" /> Javascript | A reusable Node.js command-line tool for compiling LESS files into regular `.css` and minified `.min.css` files                                                                                                                                                                                     |
| [Bash Remote SSH / rsync Helper](./Shell-Remote-SSH/)                | <img src="https://cdn.jsdelivr.net/gh/devicons/devicon@latest/icons/bash/bash-original.svg" width="24" alt="Bash"> Bash                           | Reusable Bash helper for uploading files and synchronizing directories with a remote Linux server using `rsync` over SSH                                                                                                                                                                            |

## License and author

Copyright © 2026 **Roman Drechsel** — [roman-drechsel.de](https://roman-drechsel.de).

This project is licensed under the **GNU General Public License v3.0 (GPL-3.0-only)**.

You are free to use, modify, and distribute this software, including for commercial purposes, under the terms of the GNU GPL v3.0.

See the full license text in [`LICENSE`](LICENSE) or visit the [GNU GPL v3.0 website](https://www.gnu.org/licenses/gpl-3.0.en.html).

## AI-assisted development

These scripts and their documentation were created in part with the assistance of artificial intelligence (AI), including ChatGPT. AI-assisted code is not a guarantee of correctness. Review and test the scripts for your own use case, especially before relying on automated backups or restores.
