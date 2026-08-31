#!/usr/bin/env bash
# shellcheck disable=SC2016
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib

check "Node.js 24" bash -c 'node --version | grep -E "^v24\."'
check "pnpm 11.22.0" bash -c 'cd /tmp && test "$(pnpm --version)" = "11.22.0"'
check "Python 3.12" bash -c 'python --version | grep -E "^Python 3\.12\."'
check "SkillSpector" skillspector --version
check "GitHub CLI" gh --version
check "Chromium" chromium --version
check "Vercel CLI 58.9.1" bash -c 'vercel --version | grep -F "58.9.1"'
check "Claude Code" claude --version
check "Codex" codex --version
check "Codex file credential storage" bash -c 'grep -Fq "cli_auth_credentials_store = \"file\"" "${CODEX_HOME}/config.toml"'
check "Docker storage CLI" devcontainer-docker-storage --help
check "Claude shared marketplace commit" bash -c 'test "$(git -C "${CLAUDE_CODE_PLUGIN_SEED_DIR}/marketplaces/shared-agent-plugins" rev-parse HEAD)" = "bc8512fcc88bbc7292130b37e7f371d9cd071dd0"'
check "Claude shared plugins seeded" bash -c 'for plugin in vercel-react-best-practices e2e-test-governance wio; do grep -Fq "${plugin}@shared-agent-plugins" "${CLAUDE_CODE_PLUGIN_SEED_DIR}/installed_plugins.json" || exit 1; done'
check "Claude compatibility skills linked" bash -c 'for skill in maintain-agent-instructions vercel-web-quality-optimizer; do test -L "${CLAUDE_CONFIG_DIR}/skills/${skill}" || exit 1; done'
check "Matt Pocock Skills subscribed for Claude and Codex" bash -c 'for skill in grilling writing-for-agents; do test -f "${HOME}/.agents/skills/${skill}/SKILL.md" && test -L "${CLAUDE_CONFIG_DIR}/skills/${skill}" || exit 1; done'
check "Claude shared global instructions" bash -c 'grep -Fq "# 共通作業方針" "${CLAUDE_CONFIG_DIR}/rules/shared-agent-plugins/common.md" && grep -Fq "# Claude Code固有方針" "${CLAUDE_CONFIG_DIR}/rules/shared-agent-plugins/claude.md"'
check "Codex shared marketplace pinned" bash -c 'grep -Fq "ref = \"v0.22.0\"" "${CODEX_HOME}/config.toml"'
check "Codex shared plugins enabled" bash -c 'for plugin in agent-instruction-maintenance vercel-react-best-practices vercel-web-quality e2e-test-governance wio; do grep -Fq "[plugins.\"${plugin}@shared-agent-plugins\"]" "${CODEX_HOME}/config.toml" || exit 1; done'
check "Retired Matt Pocock Plugin removed" bash -c '! grep -Fq "[plugins.\"matt-pocock-engineering@shared-agent-plugins\"]" "${CODEX_HOME}/config.toml"'
check "Codex shared global instructions" bash -c 'grep -Fq "# 共通作業方針" "${CODEX_HOME}/AGENTS.md" && grep -Fq "# Codex固有方針" "${CODEX_HOME}/AGENTS.md"'

reportResults
