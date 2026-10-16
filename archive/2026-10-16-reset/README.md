# Plenara before the October 16, 2026 reset

Historical archive. Nothing here is current product guidance or executable
project configuration. The owner requested a clean start, including designs,
skills, instructions, and implementation.

- `plenara-before-reset.tar.gz`: all 926 tracked files, with their original paths,
  from commit `fa1c955` (full commit recorded below).
- `manifest.json`: original paths and SHA-256 hashes. Every archived file was
  read back and verified byte-for-byte before the working tree was moved.
- `local-worktree/`: the complete original checkout, including ignored build
  artifacts and private local configuration. Preserved on this Mac, deliberately
  excluded from Git. It is about 20 GB; it was moved, not rebuilt or deleted.

The tar archive keeps historical source, tests, CI, agent definitions, and skills
out of automatic discovery. Recover files into a separate checkout rather than
extracting them over the new project. Git history remains available too.
fa1c955bf1d719f4d6038c2b6e3ec5f57280920b
