#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
feature_metadata="${repository_root}/src/web-dev/devcontainer-feature.json"
post_attach_script="${repository_root}/src/web-dev/post-attach.sh"

node - "${feature_metadata}" <<'NODE'
const fs = require("node:fs");

const metadata = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
const sharedMount = metadata.mounts?.find(({ target }) => target === "/shared");
if (
  sharedMount?.source !== "${localWorkspaceFolder}/../agent-repos" ||
  sharedMount?.type !== "bind"
) {
  throw new Error("/shared must bind the host's sibling agent-repos directory");
}

if (metadata.postAttachCommand !== "/usr/local/share/web-dev/post-attach.sh") {
  throw new Error("postAttachCommand must run the shared workspace script");
}
NODE

mock_root="$(mktemp -d)"
arguments_file="${mock_root}/arguments"
mkdir -p "${mock_root}/bin"
cat > "${mock_root}/bin/code" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$@" > "${MOCK_CODE_ARGUMENTS_FILE}"
MOCK
chmod +x "${mock_root}/bin/code"

PATH="${mock_root}/bin:${PATH}" \
  MOCK_CODE_ARGUMENTS_FILE="${arguments_file}" \
  bash "${post_attach_script}"

diff -u <(
  printf '%s\n' \
    --add \
    /shared/agent-config \
    /shared/shared-agent-plugins \
    /shared/shared-devcontainer-features
) "${arguments_file}"

cat > "${mock_root}/bin/code" <<'MOCK'
#!/usr/bin/env bash
exit 127
MOCK
chmod +x "${mock_root}/bin/code"

PATH="${mock_root}/bin:${PATH}" bash "${post_attach_script}"

echo "shared workspace metadata test passed"
