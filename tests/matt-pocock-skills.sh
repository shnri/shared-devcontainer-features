#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d)"
trap 'rm -rf -- "${test_root}"' EXIT

export TEST_NPX_ARGUMENTS="${test_root}/npx-arguments"
mkdir -p "${test_root}/bin"
cat > "${test_root}/bin/npx" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "${TEST_NPX_ARGUMENTS}"
EOF
chmod +x "${test_root}/bin/npx"
export PATH="${test_root}/bin:${PATH}"

# shellcheck source=/dev/null
source "${repository_root}/src/web-dev/matt-pocock-skills.sh"

sync_matt_pocock_skills true true
diff -u - "${TEST_NPX_ARGUMENTS}" <<'EOF'
--yes
skills@latest
add
mattpocock/skills
--skill
*
--agent
codex
claude-code
--global
--yes
EOF

rm -f "${TEST_NPX_ARGUMENTS}"
sync_matt_pocock_skills false false
test ! -e "${TEST_NPX_ARGUMENTS}"
