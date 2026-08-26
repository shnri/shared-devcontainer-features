#!/usr/bin/env bash
set -euo pipefail

readonly feature_dir="${WEB_DEV_INSTALL_DIR:-/usr/local/share/web-dev}"
source_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly source_dir

install_chromium="${INSTALLCHROMIUM:-true}"
vercel_version="${VERCELVERSION:-58.9.1}"
remote_user="${_REMOTE_USER:-${_CONTAINER_USER:-${USER:-}}}"
remote_home="${_REMOTE_USER_HOME:-${_CONTAINER_USER_HOME:-}}"

if [[ -z "${remote_user}" ]]; then
  remote_user="$(id -un)"
fi

if ! id "${remote_user}" >/dev/null 2>&1; then
  echo "web-dev: remote user does not exist: ${remote_user}" >&2
  exit 1
fi

if [[ -z "${remote_home}" ]]; then
  remote_home="$(getent passwd "${remote_user}" | cut -d: -f6)"
fi

if [[ -z "${remote_home}" || "${remote_home}" != /* ]]; then
  echo "web-dev: could not resolve an absolute home for ${remote_user}." >&2
  exit 1
fi

remote_group="$(id -gn "${remote_user}")"
readonly remote_user remote_home remote_group

# Featureのbuild処理がremote userのHOME配下をroot所有で残さないよう、
# user-local installerが使うcacheを先に正しい所有権で用意する。
install -d -m 0755 -o "${remote_user}" -g "${remote_group}" \
  "${remote_home}/.cache" \
  "${remote_home}/.cache/claude"

if [[ "${install_chromium}" == "true" ]]; then
  if ! command -v apt-get >/dev/null 2>&1; then
    echo "web-dev: installChromium requires a Debian-based image with apt-get." >&2
    exit 1
  fi

  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends chromium
  rm -rf /var/lib/apt/lists/*
fi

if [[ "${vercel_version}" != "none" ]]; then
  if [[ ! "${vercel_version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+([+-][0-9A-Za-z.-]+)?$ ]]; then
    echo "web-dev: vercelVersion must be an exact semantic version or 'none'." >&2
    exit 1
  fi

  if ! command -v npm >/dev/null 2>&1 && [[ -s /usr/local/share/nvm/nvm.sh ]]; then
    # The dependent Node Feature installs nvm before this Feature.
    # shellcheck source=/dev/null
    source /usr/local/share/nvm/nvm.sh
  fi

  if ! command -v npm >/dev/null 2>&1; then
    echo "web-dev: npm was not found after installing the Node Feature dependency." >&2
    exit 1
  fi

  npm install --global -- "vercel@${vercel_version}"
fi

install -d -m 0755 "${feature_dir}"
install -m 0755 "${source_dir}/post-create.sh" "${feature_dir}/post-create.sh"
install -m 0755 "${source_dir}/docker-storage.sh" \
  /usr/local/bin/devcontainer-docker-storage
install -m 0644 \
  "${source_dir}/global-instructions.sh" \
  "${feature_dir}/global-instructions.sh"

{
  printf 'install_claude_code=%q\n' "${INSTALLCLAUDECODE:-true}"
  printf 'install_codex=%q\n' "${INSTALLCODEX:-true}"
  printf 'install_shared_agent_plugins=%q\n' "${INSTALLSHAREDAGENTPLUGINS:-true}"
  printf 'install_shared_global_instructions=%q\n' "${INSTALLSHAREDGLOBALINSTRUCTIONS:-true}"
  printf 'codex_approval_policy=%q\n' "${CODEXAPPROVALPOLICY:-default}"
  printf 'codex_sandbox_mode=%q\n' "${CODEXSANDBOXMODE:-default}"
  printf 'run_docker_storage_gc_on_create=%q\n' "${RUNDOCKERSTORAGEGCONCREATE:-false}"
} > "${feature_dir}/options.env"

chmod 0644 "${feature_dir}/options.env"
