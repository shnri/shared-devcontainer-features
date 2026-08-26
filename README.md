# shared-devcontainer-features

Web projectで共通利用するDev Container Featuresです。Node.js、Python、AI開発CLI、browserなどの共通toolchainを`web-dev` FeatureとしてGHCRからバージョン配布します。

## 利用方法

consumerの`.devcontainer/devcontainer.json`からOCI Featureを参照します。CLIを常に最新版へ更新する2.xを利用する場合はmajor versionを指定します。

```jsonc
{
  "name": "my-web-project",
  "image": "mcr.microsoft.com/devcontainers/base:2.1.13-bookworm",
  "features": {
    "ghcr.io/shnri/shared-devcontainer-features/web-dev:2": {},
  },
}
```

Featureを完全に同じreleaseへ固定する場合は`:2.1.0`、minor更新だけ受け取る場合は`:2.1`を使います。Dev Containerが生成する`devcontainer-lock.json`もconsumer repositoryへcommitし、実際に解決したversionとdigestを固定してください。

このFeatureはDebian Bookworm系のDev Container imageと、標準の`vscode` user（homeは`/home/vscode`）を対象にしています。

## 含まれるもの

- Node.js 24、npm、pnpm 11.22.0
- Python 3.12、SkillSpector 2.8.2相当（commit固定）
- GitHub CLI
- Chromium、Vercel CLI 58.9.1
- post-createごとに最新版へ更新するClaude CodeとCodex
- Claude Code/CodexのVS Code extension
- Claude/Codexの認証・設定を保持するproject別named volume
- [`shnri/shared-agent-plugins`](https://github.com/shnri/shared-agent-plugins) `v0.21.0`の共通Marketplace、Plugin、Skill、global instructions

Claude CodeとCodexはremote user所有にするため、container作成後に公式standalone installerで導入します。Featureを再実行した場合も既存CLIをスキップせず、最新版へ更新します。

共通Agent Pluginはpublic Marketplaceから固定commitを取得し、両クライアントのネイティブな仕組みへ展開します。Claude Codeでは`/opt/claude-plugin-seed`を`CLAUDE_CODE_PLUGIN_SEED_DIR`として読み込み、Claude Plugin化されていない互換Skillだけを`~/.claude/skills`から固定checkoutへリンクします。Codexではユーザーの`CODEX_HOME`へMarketplaceとPluginをidempotentに登録します。固定releaseにglobal instructionsが含まれる場合、Codexは`~/.codex/AGENTS.md`のmanaged block、Claude Codeは`~/.claude/rules/shared-agent-plugins/`から読み込みます。`~/.claude/CLAUDE.md`と所有外のrulesは変更しません。どちらも新しいセッションから利用できます。

## Options

| option                      | default   | 説明                                                 |
| --------------------------- | --------- | ---------------------------------------------------- |
| `installClaudeCode`         | `true`    | Claude Codeを導入する                                |
| `installCodex`              | `true`    | Codex CLIを導入する                                  |
| `installSharedAgentPlugins` | `true`    | Claude/Codexへ固定済み共通PluginとSkillを導入する    |
| `installSharedGlobalInstructions` | `true` | 共通Plugin導入時に、固定済みのユーザー共通指示を両clientへ導入する |
| `codexApprovalPolicy`       | `default` | Codex user設定を変更しないか、承認policyを明示する   |
| `codexSandboxMode`          | `default` | Codex user設定を変更しないか、sandbox modeを明示する |
| `installChromium`           | `true`    | `/usr/bin/chromium`を導入する                        |
| `vercelVersion`             | `58.9.1`  | Vercel CLI version。`none`で導入しない               |

`codexApprovalPolicy`と`codexSandboxMode`の既定値は`default`です。Featureはconsumerの安全設定を暗黙に弱めません。Dev Container自体を外側の隔離境界として扱うprojectだけが、例えば次のように明示します。

```jsonc
"ghcr.io/shnri/shared-devcontainer-features/web-dev:2": {
  "codexApprovalPolicy": "never",
  "codexSandboxMode": "danger-full-access"
}
```

## 既存volumeを維持するconsumer

Featureの既定volume sourceには`${devcontainerId}`が含まれ、projectごとに分離されます。既存projectが別名のvolumeを使用中なら、同じtargetを`devcontainer.json`側で指定するとconsumer側の設定が優先されます。

```jsonc
"mounts": [
  "source=my-project-codex-home,target=/home/vscode/.codex,type=volume",
  "source=my-project-claude-home,target=/home/vscode/.claude,type=volume"
]
```

## Project側に残す設定

次の設定は共有Featureへ移さず、各projectの`devcontainer.json`に置きます。

- `image`、`build`、`dockerComposeFile`、`service`
- `workspaceFolder`、`workspaceMount`
- project固有のportと環境変数
- dependency installやsubmodule初期化などproject固有のlifecycle command
- project固有の`.codex/config.toml`、`.agents/skills`、`AGENTS.md`
- project固有の`.claude/settings.json`、`.claude/skills`、`.mcp.json`

Codexはprojectの`.codex/config.toml`を信頼済みrepositoryで直接読み込みます。これを`~/.codex/config.toml`へコピーすると、ユーザー共通のMarketplaceやPlugin登録を失うため、consumer側で同期処理を追加しないでください。Claude Codeでも共通Plugin Seedとproject固有の`enabledPlugins`／`extraKnownMarketplaces`は併用できます。

## Release

Featureごとのversionは`src/<feature>/devcontainer-feature.json`の`version`で管理します。release前にversionをSemVerで更新し、`main`の`Test Features` workflowが成功することを確認してください。

1. GitHubのActionsから`Release Features` workflowを`main`に対して手動実行する。
2. workflow内の再検証とGHCR publishが成功したことを確認する。
3. 初回releaseではGitHub Packagesの`shared-devcontainer-features/web-dev`を`Public`へ変更する。repository自体はprivateのままでも構わない。
4. `ghcr.io/shnri/shared-devcontainer-features/web-dev:2`が認証なしでpullできることを確認する。

publish時に`2.1.0`、`2.1`、`2`、`latest`のOCI tagがFeature仕様に従って更新されます。Featureのソースとpackageに機密情報を含めないでください。

## このrepositoryを開発する

[`.devcontainer/devcontainer.json`](.devcontainer/devcontainer.json)にNode.js 24、Dev Container CLI 0.88.0、Docker-in-Dockerを用意しています。Dev Containerで開いた後、次のcommandでFeatureをbuild testできます。

```bash
devcontainer features test --features web-dev .
```

構成と配布方法は[Dev Container Feature仕様](https://containers.dev/implementors/features/)および公式[feature-starter](https://github.com/devcontainers/feature-starter)に準拠します。
