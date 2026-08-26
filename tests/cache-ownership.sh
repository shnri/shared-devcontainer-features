#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d)"
remote_user="$(id -un)"
remote_uid="$(id -u)"
remote_gid="$(id -g)"
readonly repository_root test_root remote_user remote_uid remote_gid
readonly remote_home="${test_root}/home"
readonly feature_dir="${test_root}/feature"
readonly fake_bin="${test_root}/bin"

cleanup() {
  sudo rm -rf -- "${test_root}"
}
trap cleanup EXIT

mkdir -p "${remote_home}"

sudo env \
  WEB_DEV_INSTALL_DIR="${feature_dir}" \
  INSTALLCHROMIUM=false \
  VERCELVERSION=none \
  INSTALLCLAUDECODE=true \
  INSTALLCODEX=false \
  INSTALLSHAREDAGENTPLUGINS=false \
  INSTALLSHAREDGLOBALINSTRUCTIONS=false \
  RUNDOCKERSTORAGEGCONCREATE=false \
  _REMOTE_USER="${remote_user}" \
  _REMOTE_USER_HOME="${remote_home}" \
  bash "${repository_root}/src/web-dev/install.sh"

test "$(stat -c '%u:%g' "${remote_home}/.cache")" = \
  "${remote_uid}:${remote_gid}"
test "$(stat -c '%u:%g' "${remote_home}/.cache/claude")" = \
  "${remote_uid}:${remote_gid}"

# build後に別処理がcache ownershipを崩しても、Claude installerの直前に補正する。
sudo chown root:root "${remote_home}/.cache" "${remote_home}/.cache/claude"

mkdir -p "${fake_bin}"
cat > "${fake_bin}/curl" <<'EOF'
#!/usr/bin/env bash
cat <<'INSTALLER'
#!/usr/bin/env bash
set -euo pipefail
mkdir -p "${XDG_CACHE_HOME:-${HOME}/.cache}/claude"
touch "${XDG_CACHE_HOME:-${HOME}/.cache}/claude/installed"
INSTALLER
EOF
chmod 0755 "${fake_bin}/curl"

env \
  HOME="${remote_home}" \
  USER="${remote_user}" \
  XDG_CACHE_HOME="${remote_home}/.cache" \
  WEB_DEV_FEATURE_DIR="${feature_dir}" \
  PATH="${fake_bin}:${PATH}" \
  bash "${repository_root}/src/web-dev/post-create.sh"

test -f "${remote_home}/.cache/claude/installed"
test "$(stat -c '%u:%g' "${remote_home}/.cache")" = \
  "${remote_uid}:${remote_gid}"
test "$(stat -c '%u:%g' "${remote_home}/.cache/claude")" = \
  "${remote_uid}:${remote_gid}"

echo "cache ownership tests passed"
