#!/usr/bin/env bash
set -euo pipefail

editor_cli=""
if command -v code >/dev/null 2>&1; then
  editor_cli="code"
elif command -v code-insiders >/dev/null 2>&1; then
  editor_cli="code-insiders"
else
  # Dev Container CLIやVS Code以外のclientではExplorer操作を行わない。
  exit 0
fi

"${editor_cli}" --add \
  /shared/agent-config \
  /shared/shared-agent-plugins \
  /shared/shared-devcontainer-features
