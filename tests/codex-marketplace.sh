#!/usr/bin/env bash
# shellcheck disable=SC2034 # 動的に読み込むテスト対象関数から参照する。
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d)"
readonly repository_root test_root
readonly fake_bin="${test_root}/bin"
readonly codex_config="${test_root}/config.toml"
readonly command_log="${test_root}/commands.log"
readonly marketplace_state="${test_root}/marketplace-state"

cleanup() {
  rm -rf -- "${test_root}"
}
trap cleanup EXIT

mkdir -p "${fake_bin}"
printf '%s\n' old > "${marketplace_state}"
cat > "${codex_config}" <<'EOF'
[marketplaces.shared-agent-plugins]
source_type = "git"
source = "https://github.com/shnri/shared-agent-plugins.git"
ref = "v0.21.0"
EOF

cat > "${fake_bin}/codex" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >> "${TEST_COMMAND_LOG}"

case "$*" in
  "plugin marketplace list --json")
    if [[ "$(< "${TEST_MARKETPLACE_STATE}")" == "old" ]]; then
      root="${TEST_ROOT}/old-root"
    else
      root="${TEST_ROOT}/new-root"
    fi
    printf '{"marketplaces":[{"name":"shared-agent-plugins","root":"%s","marketplaceSource":{"sourceType":"git","source":"https://github.com/shnri/shared-agent-plugins.git"}}]}\n' "${root}"
    ;;
  "plugin marketplace remove shared-agent-plugins")
    printf '%s\n' absent > "${TEST_MARKETPLACE_STATE}"
    ;;
  "plugin marketplace add https://github.com/shnri/shared-agent-plugins.git --ref v0.23.0")
    printf '%s\n' new > "${TEST_MARKETPLACE_STATE}"
    cat > "${TEST_CODEX_CONFIG}" <<'CONFIG'
[marketplaces.shared-agent-plugins]
source_type = "git"
source = "https://github.com/shnri/shared-agent-plugins.git"
ref = "v0.23.0"
CONFIG
    ;;
  "plugin add "* | "plugin remove "*)
    ;;
  *)
    echo "unexpected codex command: $*" >&2
    exit 1
    ;;
esac
EOF

cat > "${fake_bin}/git" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "$*" == *"/old-root"* ]]; then
  printf '%s\n' old-commit
else
  printf '%s\n' f4f7091288f7e9d0d049e31ca9cd83cd226cb53c
fi
EOF
chmod 0755 "${fake_bin}/codex" "${fake_bin}/git"

export TEST_ROOT="${test_root}"
export TEST_COMMAND_LOG="${command_log}"
export TEST_MARKETPLACE_STATE="${marketplace_state}"
export TEST_CODEX_CONFIG="${codex_config}"
export PATH="${fake_bin}:${PATH}"

# shellcheck disable=SC1090
source <(sed -n '/^read_toml_section_string()/,/^}/p' \
  "${repository_root}/src/web-dev/post-create.sh")
# shellcheck disable=SC1090
source <(sed -n '/^configure_codex_shared_plugins()/,/^}/p' \
  "${repository_root}/src/web-dev/post-create.sh")

readonly shared_marketplace_name="shared-agent-plugins"
readonly shared_marketplace_repository="https://github.com/shnri/shared-agent-plugins.git"
readonly shared_marketplace_ref="v0.23.0"
readonly shared_marketplace_commit="f4f7091288f7e9d0d049e31ca9cd83cd226cb53c"
readonly -a codex_shared_plugins=("wio")
readonly -a codex_retired_plugins=("retired")

configure_codex_shared_plugins
grep -Fqx 'plugin marketplace remove shared-agent-plugins' "${command_log}"
grep -Fqx \
  'plugin marketplace add https://github.com/shnri/shared-agent-plugins.git --ref v0.23.0' \
  "${command_log}"
test "$(read_toml_section_string "${codex_config}" \
  marketplaces.shared-agent-plugins ref)" = "v0.23.0"

: > "${command_log}"
configure_codex_shared_plugins
if grep -Fq 'plugin marketplace remove' "${command_log}"; then
  echo 'matching marketplace was unnecessarily removed' >&2
  exit 1
fi
if grep -Fq 'plugin marketplace add https://' "${command_log}"; then
  echo 'matching marketplace was unnecessarily added' >&2
  exit 1
fi

sed -i 's/ref = "v0.23.0"/ref = "v0.21.0"/' "${codex_config}"
: > "${command_log}"
configure_codex_shared_plugins
grep -Fqx 'plugin marketplace remove shared-agent-plugins' "${command_log}"

echo "Codex marketplace migration tests passed"
