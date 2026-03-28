#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "$0")" && pwd)"
source_file="${repo_root}/CLAUDE.md"
target_file="${repo_root}/AGENTS.md"

if [[ ! -f "${source_file}" ]]; then
  echo "Missing source file: ${source_file}" >&2
  exit 1
fi

{
  echo "# AGENTS.md"
  echo
  echo "> This file is generated from \`CLAUDE.md\`. Edit \`CLAUDE.md\` and run \`./sync-agent-docs.sh\` to refresh this file."
  echo
  tail -n +2 "${source_file}"
} > "${target_file}"
