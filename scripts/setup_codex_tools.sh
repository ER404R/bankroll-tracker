#!/usr/bin/env bash
# Run in a normal host terminal; this Codex session cannot write its own config.
set -euo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
codex_dir=${CODEX_HOME:-"$HOME/.codex"}
rtk_bin_dir="$HOME/.local/bin"

for required_command in codex dart npx curl python3 tar; do
  if ! command -v "$required_command" >/dev/null 2>&1; then
    printf 'Required command is missing: %s\n' "$required_command" >&2
    exit 1
  fi
done
if [[ ! -f "$repo_dir/SPEC.md" ]]; then
  printf 'Run this script from its original bankroll-tracker checkout.\n' >&2
  exit 1
fi
for target_dir in "$codex_dir" "$repo_dir/.agents"; do
  if [[ -d "$target_dir" && ! -w "$target_dir" ]]; then
    printf 'Read-only setup destination: %s\nRun from a normal host terminal outside the Codex sandbox.\n' "$target_dir" >&2
    exit 1
  fi
done

cd -- "$repo_dir"
setup_tmp=$(mktemp -d)
trap 'rm -rf -- "$setup_tmp"' EXIT

# Preserve pre-install settings. RTK performs its own merge of existing hooks.
backup_dir="$codex_dir/tool-setup-backups/$(date -u +%Y%m%dT%H%M%SZ)-$$"
mkdir -p -- "$backup_dir"
for config_name in config.toml hooks.json AGENTS.md RTK.md; do
  if [[ -f "$codex_dir/$config_name" ]]; then
    cp -p -- "$codex_dir/$config_name" "$backup_dir/$config_name"
  fi
done
printf 'Existing Codex settings backed up to %s\n' "$backup_dir"

# The official plugin includes both Flutter/Dart skills and dart-mcp-server.
# dart is checked above because the bundled MCP starts `dart mcp-server`.
codex plugin marketplace add flutter/agent-plugins
codex plugin add dart-flutter@dart-flutter
dart mcp-server --help > "$setup_tmp/dart-mcp-help.txt"

# The upstream installer supplies the skill's scripts and local datasets too.
# Re-running retains an existing skill rather than overwriting local changes.
if [[ -f "$repo_dir/.agents/skills/ui-ux-pro-max/SKILL.md" ]]; then
  printf 'UI UX Pro Max already exists; retaining it.\n'
else
  npx --yes --package ui-ux-pro-max-cli uipro init --ai codex
fi
python3 - "$repo_dir/.agents/skills/ui-ux-pro-max" <<'PY'
from pathlib import Path
import subprocess
import sys

skill_dir = Path(sys.argv[1])
for relative in ('SKILL.md', 'scripts/search.py', 'data/stacks/flutter.csv'):
    if not (skill_dir / relative).is_file():
        raise SystemExit(f'Incomplete UI UX Pro Max installation: {relative}')
subprocess.run([
    sys.executable, str(skill_dir / 'scripts/search.py'),
    'responsive layout', '--stack', 'flutter',
], check=True, stdout=subprocess.DEVNULL)
print('UI UX Pro Max skill and Flutter dataset verified.')
PY

# Install the command-filter edition. Its upstream installer checks the
# release's SHA-256 checksums before installing the executable. No API proxy.
if command -v rtk >/dev/null 2>&1; then
  rtk_bin=$(command -v rtk)
else
  curl --fail --location --proto '=https' --tlsv1.2 \
    https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh \
    --output "$setup_tmp/install-rtk.sh"
  RTK_EDITION=oss RTK_INSTALL_DIR="$rtk_bin_dir" \
    sh "$setup_tmp/install-rtk.sh"
  rtk_bin="$rtk_bin_dir/rtk"
fi
export PATH="$(dirname -- "$rtk_bin"):$PATH"
"$rtk_bin" --version
"$rtk_bin" gain
# User scope avoids modifying this repository's development instructions.
"$rtk_bin" init --global --codex

printf '\nInstalled plugin and configured MCP servers:\n'
codex plugin list --json
codex mcp list
printf '\nSetup finished. Restart Codex to load the plugin, skills and MCP.\n'
printf 'In Codex, open /hooks and review/trust the new RTK hook.\n'
printf 'If a new terminal cannot find rtk, add %s to its PATH.\n' "$(dirname -- "$rtk_bin")"
