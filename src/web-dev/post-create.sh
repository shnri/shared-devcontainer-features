#!/usr/bin/env bash
set -euo pipefail

readonly feature_dir="${WEB_DEV_FEATURE_DIR:-/usr/local/share/web-dev}"

# shellcheck source=/dev/null
source "${feature_dir}/options.env"
# shellcheck source=/dev/null
source "${feature_dir}/global-instructions.sh"

: "${install_claude_code:=true}"
: "${install_codex:=true}"
: "${install_shared_agent_plugins:=true}"
: "${install_shared_global_instructions:=true}"
: "${codex_approval_policy:=default}"
: "${codex_sandbox_mode:=default}"
: "${run_docker_storage_gc_on_create:=false}"

readonly shared_marketplace_name="shared-agent-plugins"
readonly shared_marketplace_repository="https://github.com/shnri/shared-agent-plugins.git"
readonly shared_marketplace_ref="v0.21.0"
readonly shared_marketplace_commit="d8aff47059b786db2ea4f7d1a6c9729dc8421e17"

readonly -a codex_shared_plugins=(
  "agent-instruction-maintenance"
  "matt-pocock-engineering"
  "vercel-react-best-practices"
  "vercel-web-quality"
  "e2e-test-governance"
  "wio"
)

readonly -a claude_shared_plugins=(
  "vercel-react-best-practices"
  "e2e-test-governance"
  "wio"
)

readonly -a claude_compatibility_skills=(
  "maintain-agent-instructions:plugins/agent-instruction-maintenance/skills/maintain-agent-instructions"
  "diagnosing-bugs:plugins/matt-pocock-engineering/skills/diagnosing-bugs"
  "improve-codebase-architecture:plugins/matt-pocock-engineering/skills/improve-codebase-architecture"
  "codebase-design:plugins/matt-pocock-engineering/skills/codebase-design"
  "vercel-web-quality-optimizer:plugins/vercel-web-quality/skills/vercel-web-quality-optimizer"
)

shared_checkout_path=""

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

ensure_user_owned_directory() {
  local path="$1"
  local user_id=""
  local group_id=""

  user_id="$(id -u)"
  group_id="$(id -g)"

  if [[ "${user_id}" -eq 0 ]]; then
    install -d -m 0755 -o "${user_id}" -g "${group_id}" "${path}"
  elif command -v sudo >/dev/null 2>&1; then
    sudo install -d -m 0755 -o "${user_id}" -g "${group_id}" "${path}"
  else
    mkdir -p "${path}"
  fi

  if [[ ! -w "${path}" ]]; then
    echo "web-dev: ${path} is not writable by the remote user." >&2
    exit 1
  fi
}

prepare_shared_marketplace_checkout() (
  local marketplace_root="$1"
  local checkout_path="${marketplace_root}/${shared_marketplace_name}"
  local checkout_commit=""
  local temporary_checkout=""

  if [[ -d "${checkout_path}/.git" ]]; then
    checkout_commit="$(git -C "${checkout_path}" rev-parse HEAD 2>/dev/null || true)"
  fi

  if [[ "${checkout_commit}" == "${shared_marketplace_commit}" ]]; then
    return
  fi

  temporary_checkout="$(mktemp -d "${marketplace_root}/.${shared_marketplace_name}.XXXXXX")"
  trap '
    if [[ -n "${temporary_checkout}" && -d "${temporary_checkout}" ]]; then
      rm -rf -- "${temporary_checkout}"
    fi
  ' EXIT

  echo "web-dev: fetching ${shared_marketplace_name} ${shared_marketplace_ref}..."
  git clone --quiet --depth 1 --branch "${shared_marketplace_ref}" \
    "${shared_marketplace_repository}" "${temporary_checkout}"

  checkout_commit="$(git -C "${temporary_checkout}" rev-parse HEAD)"
  if [[ "${checkout_commit}" != "${shared_marketplace_commit}" ]]; then
    echo "web-dev: ${shared_marketplace_ref} resolved to unexpected commit ${checkout_commit}." >&2
    exit 1
  fi

  rm -rf -- "${checkout_path}"
  mv "${temporary_checkout}" "${checkout_path}"
  temporary_checkout=""
)

configure_claude_shared_plugins() {
  local seed_dir="$1"
  local marketplace_root="${seed_dir}/marketplaces"
  local checkout_path="${marketplace_root}/${shared_marketplace_name}"
  local plugin=""
  local skill=""
  local skill_name=""
  local skill_source=""
  local skill_link=""

  ensure_user_directory "${marketplace_root}"
  prepare_shared_marketplace_checkout "${marketplace_root}"
  shared_checkout_path="${checkout_path}"

  # Seed metadata is rebuilt from the pinned checkout so repeated postCreate runs
  # cannot keep stale plugin cache entries from an older Feature release.
  rm -rf -- "${seed_dir}/cache"
  rm -f -- "${seed_dir}/known_marketplaces.json" "${seed_dir}/installed_plugins.json"

  (
    local isolated_home=""
    isolated_home="$(mktemp -d)"
    trap 'rm -rf -- "${isolated_home}"' EXIT

    env -u CLAUDE_CODE_PLUGIN_SEED_DIR \
      HOME="${isolated_home}" \
      CLAUDE_CONFIG_DIR="${isolated_home}/.claude" \
      CLAUDE_CODE_PLUGIN_CACHE_DIR="${seed_dir}" \
      claude plugin marketplace add "${checkout_path}"

    for plugin in "${claude_shared_plugins[@]}"; do
      env -u CLAUDE_CODE_PLUGIN_SEED_DIR \
        HOME="${isolated_home}" \
        CLAUDE_CONFIG_DIR="${isolated_home}/.claude" \
        CLAUDE_CODE_PLUGIN_CACHE_DIR="${seed_dir}" \
        claude plugin install --yes "${plugin}@${shared_marketplace_name}"
    done
  )

  ensure_user_directory "${claude_home}/skills"
  for skill in "${claude_compatibility_skills[@]}"; do
    skill_name="${skill%%:*}"
    skill_source="${checkout_path}/${skill#*:}"
    skill_link="${claude_home}/skills/${skill_name}"

    if [[ -e "${skill_link}" && ! -L "${skill_link}" ]]; then
      echo "web-dev: keeping existing Claude skill at ${skill_link}." >&2
      continue
    fi

    ln -sfn "${skill_source}" "${skill_link}"
  done
}

configure_codex_shared_plugins() {
  local checkout_commit=""
  local marketplace_root=""
  local plugin=""

  codex plugin marketplace add shnri/shared-agent-plugins --ref "${shared_marketplace_ref}"
  marketplace_root="$(
    codex plugin marketplace list --json |
      node -e '
        let input = "";
        process.stdin.setEncoding("utf8");
        process.stdin.on("data", (chunk) => { input += chunk; });
        process.stdin.on("end", () => {
          const marketplace = JSON.parse(input).marketplaces.find(
            ({ name }) => name === "shared-agent-plugins",
          );
          if (!marketplace) process.exit(1);
          process.stdout.write(marketplace.root);
        });
      '
  )"
  checkout_commit="$(git -C "${marketplace_root}" rev-parse HEAD)"
  if [[ "${checkout_commit}" != "${shared_marketplace_commit}" ]]; then
    echo "web-dev: Codex marketplace resolved to unexpected commit ${checkout_commit}." >&2
    echo "web-dev: remove the existing ${shared_marketplace_name} registration before rebuilding." >&2
    exit 1
  fi
  shared_checkout_path="${marketplace_root}"

  for plugin in "${codex_shared_plugins[@]}"; do
    codex plugin add "${plugin}@${shared_marketplace_name}"
  done
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

if [[ "${install_claude_code}" == "true" ]]; then
  claude_cache_home="${XDG_CACHE_HOME:-${HOME}/.cache}"
  ensure_user_owned_directory "${claude_cache_home}"
  ensure_user_owned_directory "${claude_cache_home}/claude"

  echo "web-dev: installing the latest Claude Code..."
  curl --retry 3 --connect-timeout 20 -fsSL https://claude.ai/install.sh |
    bash -s -- latest
fi

if [[ "${install_codex}" == "true" ]]; then
  echo "web-dev: installing the latest Codex..."
  curl --retry 3 --connect-timeout 20 -fsSL https://chatgpt.com/codex/install.sh |
    CODEX_RELEASE=latest CODEX_NON_INTERACTIVE=true sh
fi

if [[ "${install_shared_agent_plugins}" == "true" ]]; then
  if [[ "${install_claude_code}" == "true" ]]; then
    if ! command -v claude >/dev/null 2>&1; then
      echo "web-dev: Claude Code is required to build the shared plugin seed." >&2
      exit 1
    fi

    claude_seed_dir="${CLAUDE_CODE_PLUGIN_SEED_DIR:-/opt/claude-plugin-seed}"
    ensure_user_directory "${claude_seed_dir}"
    configure_claude_shared_plugins "${claude_seed_dir}"
  fi

  if [[ "${install_codex}" == "true" ]]; then
    if ! command -v codex >/dev/null 2>&1; then
      echo "web-dev: Codex is required to install the shared plugins." >&2
      exit 1
    fi

    configure_codex_shared_plugins
  fi

  if [[ "${install_shared_global_instructions}" == "true" &&
    -n "${shared_checkout_path}" ]]; then
    install_shared_global_instructions \
      "${shared_checkout_path}" \
      "${shared_marketplace_ref}" \
      "${shared_marketplace_commit}" \
      "${codex_home}" \
      "${claude_home}" \
      "${install_codex}" \
      "${install_claude_code}"
  fi
fi

# Remove the legacy alias used before Codex had persisted permission settings.
if [[ -f "${HOME}/.bashrc" ]]; then
  sed -i \
    "/^[[:space:]]*alias codex='codex --dangerously-bypass-approvals-and-sandbox'[[:space:]]*$/d" \
    "${HOME}/.bashrc"
fi

# 専用DinDを持つconsumerだけが明示的に有効化する。host daemonを共有するconsumerへ
# BuildKit保持量を暗黙に強制しない。
if [[ "${run_docker_storage_gc_on_create}" == "true" ]]; then
  if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    devcontainer-docker-storage gc
  else
    echo 'web-dev: Docker daemon is unavailable; skipped safe Docker storage GC.' >&2
  fi
fi
