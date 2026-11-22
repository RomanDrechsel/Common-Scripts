# Linux Scripts

A collection of useful scripts for Linux, automation,
backup and software development.

## Available scripts

| Script                                                               | Language                                                                                                                        | Description                                                                                                                                                                                                                                                                                         |
| -------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [Font Subset](./Font-Subsets/)                                       | <img src="https://cdn.jsdelivr.net/gh/devicons/devicon@latest/icons/python/python-original.svg" width="24" alt="Python"> Python | Create optimized WOFF2, WOFF, TTF or OTF font subsets.<br /><br /> This script recursively scans files in a directory, collects the Unicode codepoints used in those files and creates a reduced font from a TTF or OTF source font.                                                                |
| [Large Thunderbird / Betterbird Backup](./Large-Thunderbird-Backup/) | <img src="https://cdn.jsdelivr.net/gh/devicons/devicon@latest/icons/bash/bash-original.svg" width="24" alt="Bash"> Bash         | Backup and restore Thunderbird and Betterbird settings and e-mails, if the profile is larger than 2 GB.<br /><br /> Thunderbird / Betterbird can only im- and export profiles, that are smaller than 2 GB. This script creates a zip-achive from the profile, that can be copied into a new profile |
| [Bash Remote SSH / rsync Helper](./Shell-Remote-SSH/)                | <img src="https://cdn.jsdelivr.net/gh/devicons/devicon@latest/icons/bash/bash-original.svg" width="24" alt="Bash"> Bash         | Reusable Bash helper for uploading files and synchronizing directories with a remote Linux server using `rsync` over SSH                                                                                                                                                                            |

## AI-assisted development

These scripts and their documentation were created in part with the assistance of artificial intelligence (AI), including ChatGPT. AI-assisted code is not a guarantee of correctness. Review and test the scripts for your own use case, especially before relying on automated backups or restores.
