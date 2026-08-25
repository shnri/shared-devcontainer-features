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
check "Chromium skipped" bash -c '! command -v chromium'
check "Vercel skipped" bash -c '! command -v vercel'
check "Claude Code skipped" bash -c '! command -v claude'
check "Codex skipped" bash -c '! command -v codex'
check "Codex config initialized" bash -c 'grep -Fq "cli_auth_credentials_store = \"file\"" "${CODEX_HOME}/config.toml"'
check "Shared plugins skipped without agent CLIs" bash -c 'test ! -e "${CLAUDE_CODE_PLUGIN_SEED_DIR}/installed_plugins.json"'

reportResults
