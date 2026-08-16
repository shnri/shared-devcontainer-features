#!/usr/bin/env bash
# shellcheck disable=SC2016
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib

check "Node.js 24" bash -c 'node --version | grep -E "^v24\."'
check "pnpm 11.22.0" bash -c 'test "$(pnpm --version)" = "11.22.0"'
check "Python 3.12" bash -c 'python --version | grep -E "^Python 3\.12\."'
check "SkillSpector" skillspector --version
check "GitHub CLI" gh --version
check "Chromium" chromium --version
check "Vercel CLI 58.9.1" bash -c 'vercel --version | grep -F "58.9.1"'
check "Claude Code 2.1.233" bash -c 'claude --version | grep -F "2.1.233"'
check "Codex 0.147.0" bash -c 'codex --version | grep -F "0.147.0"'
check "Codex file credential storage" bash -c 'grep -Fq "cli_auth_credentials_store = \"file\"" "${CODEX_HOME}/config.toml"'

reportResults
