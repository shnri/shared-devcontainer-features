#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "${repository_root}/src/web-dev/global-instructions.sh"

fixture_root="$(mktemp -d)"
trap 'rm -rf -- "${fixture_root}"' EXIT

codex_home="${fixture_root}/codex"
claude_home="${fixture_root}/claude"
owned_root="${claude_home}/rules/shared-agent-plugins"
mkdir -p -- "${codex_home}" "${owned_root}"

fail() {
  echo "global-instructions test failed: $*" >&2
  exit 1
}

assert_contains() {
  local path="$1"
  local expected="$2"
  grep -Fq -- "${expected}" "${path}" || fail "${path} does not contain ${expected}"
}

# shellcheck disable=SC2154
printf '# Personal Codex\n\nkeep me\n\n%s\n# Common v1\n%s\n\n<!-- agent-config:start -->\n@/home/user/agent-config/claude/CLAUDE.md\n<!-- agent-config:end -->\n' \
  "${shared_instructions_begin}" "${shared_instructions_end}" > "${codex_home}/AGENTS.md"
printf '# Personal Claude\n\nkeep me\n' > "${claude_home}/CLAUDE.md"
printf '# Personal rule\n\nkeep me\n' > "${claude_home}/rules/personal.md"
printf '# Common v1\n' > "${owned_root}/common.md"
printf '# Claude v1\n' > "${owned_root}/claude.md"
printf '{}\n' > "${owned_root}/.source.json"

remove_shared_global_instructions "${codex_home}" "${claude_home}" true true

assert_contains "${codex_home}/AGENTS.md" '# Personal Codex'
assert_contains "${codex_home}/AGENTS.md" '<!-- agent-config:start -->'
! grep -Fq -- "${shared_instructions_begin}" "${codex_home}/AGENTS.md" ||
  fail 'Codex managed block was not removed'
! grep -Fq -- '# Common v1' "${codex_home}/AGENTS.md" ||
  fail 'Codex managed block content was not removed'
[[ ! -e "${owned_root}" ]] || fail 'Claude owned rules were not removed'
assert_contains "${claude_home}/rules/personal.md" '# Personal rule'
assert_contains "${claude_home}/CLAUDE.md" '# Personal Claude'
diff -u - "${codex_home}/AGENTS.md" <<'EXPECTED' || fail 'Codex file layout changed beyond the managed block'
# Personal Codex

keep me

<!-- agent-config:start -->
@/home/user/agent-config/claude/CLAUDE.md
<!-- agent-config:end -->
EXPECTED

codex_hash="$(sha256sum "${codex_home}/AGENTS.md")"
remove_shared_global_instructions "${codex_home}" "${claude_home}" true true
[[ "${codex_hash}" == "$(sha256sum "${codex_home}/AGENTS.md")" ]] ||
  fail 'Cleanup rerun was not idempotent'

block_only_home="${fixture_root}/block-only"
mkdir -p -- "${block_only_home}"
printf '%s\n# Common v1\n%s\n' \
  "${shared_instructions_begin}" "${shared_instructions_end}" > "${block_only_home}/AGENTS.md"
remove_codex_shared_instructions "${block_only_home}"
[[ ! -e "${block_only_home}/AGENTS.md" ]] ||
  fail 'File containing only the managed block was not removed'

remove_shared_global_instructions \
  "${fixture_root}/missing-codex" "${fixture_root}/missing-claude" true true
[[ ! -e "${fixture_root}/missing-codex" && ! -e "${fixture_root}/missing-claude" ]] ||
  fail 'Cleanup created directories that did not exist'

skip_home="${fixture_root}/skip"
mkdir -p -- "${skip_home}/codex" "${skip_home}/claude/rules/shared-agent-plugins"
printf '%s\n%s\n' "${shared_instructions_begin}" "${shared_instructions_end}" > "${skip_home}/codex/AGENTS.md"
printf '# Common\n' > "${skip_home}/claude/rules/shared-agent-plugins/common.md"
remove_shared_global_instructions "${skip_home}/codex" "${skip_home}/claude" false false
[[ -f "${skip_home}/codex/AGENTS.md" && -d "${skip_home}/claude/rules/shared-agent-plugins" ]] ||
  fail 'Disabled clients were cleaned'

malformed_home="${fixture_root}/malformed"
mkdir -p -- "${malformed_home}"
printf '%s\nno end marker\n' "${shared_instructions_begin}" > "${malformed_home}/AGENTS.md"
malformed_hash="$(sha256sum "${malformed_home}/AGENTS.md")"
if remove_codex_shared_instructions "${malformed_home}"; then
  fail 'Malformed Codex markers were accepted'
fi
[[ "${malformed_hash}" == "$(sha256sum "${malformed_home}/AGENTS.md")" ]] ||
  fail 'Malformed Codex file changed after rejection'

unsafe_codex_home="${fixture_root}/unsafe-codex"
unsafe_codex_target="${fixture_root}/unsafe-codex-target.md"
mkdir -p -- "${unsafe_codex_home}"
printf '%s\n%s\n' "${shared_instructions_begin}" "${shared_instructions_end}" > "${unsafe_codex_target}"
ln -s -- "${unsafe_codex_target}" "${unsafe_codex_home}/AGENTS.md"
if remove_codex_shared_instructions "${unsafe_codex_home}"; then
  fail 'Symlinked Codex instructions were accepted'
fi
assert_contains "${unsafe_codex_target}" "${shared_instructions_begin}"

unknown_home="${fixture_root}/unknown-claude"
mkdir -p -- "${unknown_home}/rules/shared-agent-plugins"
printf 'unknown\n' > "${unknown_home}/rules/shared-agent-plugins/unknown.md"
if remove_claude_shared_instructions "${unknown_home}"; then
  fail 'Unknown Claude owned rule was accepted'
fi
assert_contains "${unknown_home}/rules/shared-agent-plugins/unknown.md" 'unknown'

echo 'Legacy global instructions cleanup tests passed.'
