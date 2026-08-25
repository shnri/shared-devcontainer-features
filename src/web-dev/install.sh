#!/usr/bin/env bash
set -euo pipefail

readonly feature_dir="${WEB_DEV_INSTALL_DIR:-/usr/local/share/web-dev}"
source_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly source_dir

install_chromium="${INSTALLCHROMIUM:-true}"
vercel_version="${VERCELVERSION:-58.9.1}"

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

{
  printf 'install_claude_code=%q\n' "${INSTALLCLAUDECODE:-true}"
  printf 'install_codex=%q\n' "${INSTALLCODEX:-true}"
  printf 'install_shared_agent_plugins=%q\n' "${INSTALLSHAREDAGENTPLUGINS:-true}"
  printf 'codex_approval_policy=%q\n' "${CODEXAPPROVALPOLICY:-default}"
  printf 'codex_sandbox_mode=%q\n' "${CODEXSANDBOXMODE:-default}"
} > "${feature_dir}/options.env"

chmod 0644 "${feature_dir}/options.env"
