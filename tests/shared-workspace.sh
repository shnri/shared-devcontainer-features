#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
feature_metadata="${repository_root}/src/web-dev/devcontainer-feature.json"

node - "${feature_metadata}" <<'NODE'
const fs = require("node:fs");

const metadata = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
const sharedMount = metadata.mounts?.find(({ target }) => target === "/shared");
const expectedPostAttachCommand = [
  "code",
  "--add",
  "/shared/agent-config",
  "/shared/shared-agent-plugins",
  "/shared/shared-devcontainer-features",
];

if (
  sharedMount?.source !== "${localWorkspaceFolder}/../agent-repos" ||
  sharedMount?.type !== "bind"
) {
  throw new Error("/shared must bind the host's sibling agent-repos directory");
}

if (
  JSON.stringify(metadata.postAttachCommand) !==
  JSON.stringify(expectedPostAttachCommand)
) {
  throw new Error("postAttachCommand must add all shared repositories to VS Code");
}
NODE

echo "shared workspace metadata test passed"
