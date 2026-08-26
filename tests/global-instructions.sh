#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "${repository_root}/src/web-dev/global-instructions.sh"

fixture_root="$(mktemp -d)"
trap 'rm -rf -- "${fixture_root}"' EXIT

checkout_root="${fixture_root}/checkout"
source_root="${checkout_root}/global-instructions"
codex_home="${fixture_root}/codex"
claude_home="${fixture_root}/claude"
mkdir -p -- "${source_root}" "${codex_home}" "${claude_home}/rules"

printf '# Common v1\n\n- shared v1\n' > "${source_root}/common.md"
printf '# Claude v1\n\n- claude v1\n' > "${source_root}/claude.md"
printf '# Codex v1\n\n- codex v1\n' > "${source_root}/codex.md"
printf '# Personal Codex\n\nkeep me\n' > "${codex_home}/AGENTS.md"
printf '# Personal Claude\n\nkeep me\n' > "${claude_home}/CLAUDE.md"
printf '# Personal rule\n\nkeep me\n' > "${claude_home}/rules/personal.md"

fail() {
  echo "global-instructions test failed: $*" >&2
  exit 1
}

assert_contains() {
  local path="$1"
  local expected="$2"
  grep -Fq -- "${expected}" "${path}" || fail "${path} does not contain ${expected}"
}

install_shared_global_instructions \
  "${checkout_root}" v1 commit-v1 \
  "${codex_home}" "${claude_home}" true true

assert_contains "${codex_home}/AGENTS.md" '# Personal Codex'
# shellcheck disable=SC2154
assert_contains "${codex_home}/AGENTS.md" "${shared_instructions_begin}"
assert_contains "${codex_home}/AGENTS.md" '# Common v1'
assert_contains "${codex_home}/AGENTS.md" '# Codex v1'
assert_contains "${claude_home}/rules/shared-agent-plugins/common.md" '# Common v1'
assert_contains "${claude_home}/rules/shared-agent-plugins/claude.md" '# Claude v1'
assert_contains "${claude_home}/rules/personal.md" '# Personal rule'
assert_contains "${claude_home}/CLAUDE.md" '# Personal Claude'
[[ "$(grep -Fxc -- "${shared_instructions_begin}" "${codex_home}/AGENTS.md")" == "1" ]] ||
  fail 'Codex managed block was not installed exactly once'

codex_only_home="${fixture_root}/codex-only"
claude_only_home="${fixture_root}/claude-only"
install_shared_global_instructions \
  "${checkout_root}" v1 commit-v1 \
  "${codex_only_home}" "${fixture_root}/unused-claude" true false
assert_contains "${codex_only_home}/AGENTS.md" '# Codex v1'
[[ ! -e "${fixture_root}/unused-claude/rules/shared-agent-plugins" ]] ||
  fail 'Codex-only install created Claude rules'
install_shared_global_instructions \
  "${checkout_root}" v1 commit-v1 \
  "${fixture_root}/unused-codex" "${claude_only_home}" false true
assert_contains "${claude_only_home}/rules/shared-agent-plugins/claude.md" '# Claude v1'
[[ ! -e "${fixture_root}/unused-codex/AGENTS.md" ]] ||
  fail 'Claude-only install created Codex instructions'

codex_hash="$(sha256sum "${codex_home}/AGENTS.md")"
claude_rules_hash="$({
  sha256sum "${claude_home}/rules/shared-agent-plugins/common.md"
  sha256sum "${claude_home}/rules/shared-agent-plugins/claude.md"
  sha256sum "${claude_home}/rules/shared-agent-plugins/.source.json"
})"
install_shared_global_instructions \
  "${checkout_root}" v1 commit-v1 \
  "${codex_home}" "${claude_home}" true true
[[ "${codex_hash}" == "$(sha256sum "${codex_home}/AGENTS.md")" ]] ||
  fail 'Codex reinstall was not idempotent'
[[ "${claude_rules_hash}" == "$({
  sha256sum "${claude_home}/rules/shared-agent-plugins/common.md"
  sha256sum "${claude_home}/rules/shared-agent-plugins/claude.md"
  sha256sum "${claude_home}/rules/shared-agent-plugins/.source.json"
})" ]] || fail 'Claude reinstall was not idempotent'

malformed_before="$(sha256sum "${codex_home}/AGENTS.md")"
printf '%s\n' "${shared_instructions_begin}" >> "${codex_home}/AGENTS.md"
malformed_hash="$(sha256sum "${codex_home}/AGENTS.md")"
if install_codex_shared_instructions \
  "${source_root}" v1 commit-v1 "${codex_home}"; then
  fail 'Malformed Codex markers were accepted'
fi
[[ "${malformed_hash}" == "$(sha256sum "${codex_home}/AGENTS.md")" ]] ||
  fail 'Malformed Codex file changed after rejection'
sed -i '$d' "${codex_home}/AGENTS.md"
[[ "${malformed_before}" == "$(sha256sum "${codex_home}/AGENTS.md")" ]] ||
  fail 'Codex marker fixture was not restored'

unsafe_codex_home="${fixture_root}/unsafe-codex"
unsafe_codex_target="${fixture_root}/unsafe-codex-target.md"
mkdir -p -- "${unsafe_codex_home}"
printf '# External target\n' > "${unsafe_codex_target}"
ln -s -- "${unsafe_codex_target}" "${unsafe_codex_home}/AGENTS.md"
if install_codex_shared_instructions \
  "${source_root}" v1 commit-v1 "${unsafe_codex_home}"; then
  fail 'Symlinked Codex instructions were accepted'
fi
assert_contains "${unsafe_codex_target}" '# External target'

printf 'unknown\n' > "${claude_home}/rules/shared-agent-plugins/unknown.md"
if install_claude_shared_instructions \
  "${source_root}" v1 commit-v1 "${claude_home}"; then
  fail 'Unknown Claude owned rule was accepted'
fi
assert_contains "${claude_home}/rules/shared-agent-plugins/unknown.md" 'unknown'
rm -f -- "${claude_home}/rules/shared-agent-plugins/unknown.md"

printf '# Common v2\n\n- shared v2\n' > "${source_root}/common.md"
install_shared_global_instructions \
  "${checkout_root}" v2 commit-v2 \
  "${codex_home}" "${claude_home}" true true
assert_contains "${codex_home}/AGENTS.md" '# Common v2'
assert_contains "${claude_home}/rules/shared-agent-plugins/common.md" '# Common v2'
assert_contains "${codex_home}/AGENTS.md" '# Personal Codex'
assert_contains "${claude_home}/CLAUDE.md" '# Personal Claude'

printf '# Common v1\n\n- shared v1\n' > "${source_root}/common.md"
install_shared_global_instructions \
  "${checkout_root}" v1 commit-v1 \
  "${codex_home}" "${claude_home}" true true
assert_contains "${codex_home}/AGENTS.md" '# Common v1'
assert_contains "${claude_home}/rules/shared-agent-plugins/common.md" '# Common v1'

empty_checkout="${fixture_root}/empty-checkout"
mkdir -p -- "${empty_checkout}"
install_shared_global_instructions \
  "${empty_checkout}" old old \
  "${codex_home}" "${claude_home}" true true

echo 'Global instructions installer tests passed.'
