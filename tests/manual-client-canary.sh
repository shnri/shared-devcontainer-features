#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
shared_checkout="${1:?Usage: manual-client-canary.sh <shared-agent-plugins-checkout> <consumer-repository>}"
consumer_repository="${2:?Usage: manual-client-canary.sh <shared-agent-plugins-checkout> <consumer-repository>}"
source_ref="${SOURCE_REF:-working-tree}"
source_commit="${SOURCE_COMMIT:-dirty}"
original_codex_home="${CODEX_HOME:-${HOME}/.codex}"
original_claude_home="${CLAUDE_CONFIG_DIR:-${HOME}/.claude}"
canary_clients=",${CANARY_CLIENTS:-codex,claude},"

# shellcheck source=/dev/null
source "${repository_root}/src/web-dev/global-instructions.sh"

canary_root="$(mktemp -d)"
trap 'rm -rf -- "${canary_root}"' EXIT

install_codex=false
install_claude=false
[[ "${canary_clients}" == *,codex,* ]] && install_codex=true
[[ "${canary_clients}" == *,claude,* ]] && install_claude=true

install_shared_global_instructions \
  "${shared_checkout}" "${source_ref}" "${source_commit}" \
  "${canary_root}/codex" "${canary_root}/claude" \
  "${install_codex}" "${install_claude}"

if [[ "${install_codex}" == "true" ]]; then
  if [[ ! -f "${original_codex_home}/auth.json" ]]; then
    echo 'Codex canary skipped: auth.json was not found.' >&2
    exit 2
  fi
  ln -s -- "${original_codex_home}/auth.json" "${canary_root}/codex/auth.json"

  CODEX_HOME="${canary_root}/codex" codex exec \
    --ephemeral \
    --sandbox read-only \
    -C "${consumer_repository}" \
    'Read-only configuration canary. Do not run tools or modify files. Respond in Japanese with exactly four short lines: (1) the exact top-level heading of the shared common instruction, (2) the exact top-level heading of the Codex-specific shared instruction, (3) the exact title of this repository instruction, and (4) the repository rule for destructive Git operations. Do not infer missing headings; write MISSING if unavailable.'
fi

if [[ "${install_claude}" == "true" ]]; then
  for auth_file in .claude.json .credentials.json; do
    if [[ ! -f "${original_claude_home}/${auth_file}" ]]; then
      echo "Claude canary skipped: ${auth_file} was not found." >&2
      exit 2
    fi
    install -m 600 -- \
      "${original_claude_home}/${auth_file}" \
      "${canary_root}/claude/${auth_file}"
  done

  (
    cd "${consumer_repository}"
    CLAUDE_CONFIG_DIR="${canary_root}/claude" claude \
      -p \
      --no-session-persistence \
      --permission-mode plan \
      --tools '' \
      --output-format text \
      'Read-only configuration canary. Do not use tools or modify files. Respond in Japanese with exactly four short lines: (1) the exact top-level heading of the shared common user rule, (2) the exact top-level heading of the Claude-specific shared user rule, (3) the exact title imported from this repository AGENTS.md, and (4) the exact repository instruction line that lists commit, push, reset, merge, and rebase. Do not infer or substitute another safety rule; write MISSING if that line is unavailable.'
  )
fi
