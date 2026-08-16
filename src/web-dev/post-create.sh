#!/usr/bin/env bash
set -euo pipefail

readonly feature_dir="${WEB_DEV_FEATURE_DIR:-/usr/local/share/web-dev}"

# shellcheck source=/dev/null
source "${feature_dir}/options.env"

: "${install_claude_code:=true}"
: "${claude_code_version:=2.1.233}"
: "${install_codex:=true}"
: "${codex_version:=0.147.0}"
: "${codex_approval_policy:=default}"
: "${codex_sandbox_mode:=default}"

validate_release() {
  local name="$1"
  local value="$2"
  local channels="$3"

  if [[ " ${channels} " == *" ${value} "* ]] ||
    [[ "${value}" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]]; then
    return
  fi

  echo "web-dev: invalid ${name}: ${value}" >&2
  exit 1
}

ensure_user_directory() {
  local path="$1"

  if [[ "$(id -u)" -eq 0 ]]; then
    mkdir -p "${path}"
    chown -R "$(id -u):$(id -g)" "${path}"
  elif command -v sudo >/dev/null 2>&1; then
    sudo mkdir -p "${path}"
    sudo chown -R "$(id -u):$(id -g)" "${path}"
  else
    mkdir -p "${path}"
  fi
}

set_codex_root_string() {
  local config="$1"
  local key="$2"
  local value="$3"

  if awk -v key="${key}" '
    /^[[:space:]]*\[/ { exit }
    $0 ~ "^[[:space:]]*" key "[[:space:]]*=" { found = 1; exit }
    END { exit(found ? 0 : 1) }
  ' "${config}"; then
    sed -Ei \
      "0,/^[[:space:]]*${key}[[:space:]]*=.*$/s//${key} = \"${value}\"/" \
      "${config}"
  elif [[ ! -s "${config}" ]]; then
    printf '%s = "%s"\n' "${key}" "${value}" >> "${config}"
  else
    sed -i "1i${key} = \"${value}\"" "${config}"
  fi
}

codex_home="${CODEX_HOME:-${HOME}/.codex}"
claude_home="${CLAUDE_CONFIG_DIR:-${HOME}/.claude}"
codex_config="${codex_home}/config.toml"

ensure_user_directory "${codex_home}"
ensure_user_directory "${claude_home}"
touch "${codex_config}"

# File storage keeps CLI and IDE authentication in the mounted CODEX_HOME.
set_codex_root_string "${codex_config}" "cli_auth_credentials_store" "file"

if [[ "${codex_approval_policy}" != "default" ]]; then
  set_codex_root_string "${codex_config}" "approval_policy" "${codex_approval_policy}"
fi

if [[ "${codex_sandbox_mode}" != "default" ]]; then
  set_codex_root_string "${codex_config}" "sandbox_mode" "${codex_sandbox_mode}"
fi

export PATH="${HOME}/.local/bin:${PATH}"

if [[ "${install_claude_code}" == "true" ]] && ! command -v claude >/dev/null 2>&1; then
  validate_release "claudeCodeVersion" "${claude_code_version}" "stable latest"
  echo "web-dev: installing Claude Code ${claude_code_version}..."
  curl --retry 3 --connect-timeout 20 -fsSL https://claude.ai/install.sh |
    bash -s -- "${claude_code_version}"
fi

if [[ "${install_codex}" == "true" ]] && ! command -v codex >/dev/null 2>&1; then
  validate_release "codexVersion" "${codex_version}" "latest"
  echo "web-dev: installing Codex ${codex_version}..."
  curl --retry 3 --connect-timeout 20 -fsSL https://chatgpt.com/codex/install.sh |
    CODEX_RELEASE="${codex_version}" CODEX_NON_INTERACTIVE=true sh
fi

# Remove the legacy alias used before Codex had persisted permission settings.
if [[ -f "${HOME}/.bashrc" ]]; then
  sed -i \
    "/^[[:space:]]*alias codex='codex --dangerously-bypass-approvals-and-sandbox'[[:space:]]*$/d" \
    "${HOME}/.bashrc"
fi
