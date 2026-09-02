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

Featureを完全に同じreleaseへ固定する場合は`:3.1.0`、minor更新だけ受け取る場合は`:3.1`を使います。Dev Containerが生成する`devcontainer-lock.json`もconsumer repositoryへcommitし、実際に解決したversionとdigestを固定してください。

このFeatureはDebian Bookworm系のDev Container imageと、標準の`vscode` user（homeは`/home/vscode`）を対象にしています。

## 含まれるもの

- Node.js 24、npm、pnpm 11.22.0
- Python 3.12、SkillSpector 2.8.2相当（commit固定）
- GitHub CLI
- Chromium、Vercel CLI 58.9.1
- post-createごとに最新版へ更新するClaude CodeとCodex
- Claude Code/CodexのVS Code extension
- Claude/Codexの認証・設定を保持するproject別named volume
- hostの共有repo置き場を`/shared`へmountし、VS Code接続時に3つの共有repoをExplorerへ自動追加
- Docker daemon境界を表示し、DinDで安全なlabel限定GCを行う`devcontainer-docker-storage`
- [`shnri/shared-agent-plugins`](https://github.com/shnri/shared-agent-plugins) `v0.23.0`の共通Marketplace、Plugin、Skill
- post-createごとに[`mattpocock/skills`](https://github.com/mattpocock/skills)を再走査し、全SkillをClaude CodeとCodexへ同期する購読

Claude CodeとCodexはremote user所有にするため、container作成後に公式standalone installerで導入します。Featureを再実行した場合も既存CLIをスキップせず、最新版へ更新します。

共通Agent Pluginはpublic Marketplaceから固定commitを取得し、両クライアントのネイティブな仕組みへ展開します。Claude Codeでは`/opt/claude-plugin-seed`を`CLAUDE_CODE_PLUGIN_SEED_DIR`として読み込み、Claude Plugin化されていない互換Skillだけを`~/.claude/skills`から固定checkoutへリンクします。Codexではユーザーの`CODEX_HOME`へMarketplaceとPluginをidempotentに登録します。全projectに共通する常時指示はこのFeatureの責務外で、[`shnri/agent-config`](https://github.com/shnri/agent-config)を`git clone`して`install.sh`を実行して接続します。3.0.0以降のpost-createは、2.x系が`~/.codex/AGENTS.md`のmanaged blockと`~/.claude/rules/shared-agent-plugins/`へ配置した旧指示だけを取り除き、それ以外のユーザー指示fileは変更しません。

Matt PocockのSkillは共有Pluginへコピーしません。post-createごとに`npx --yes skills@latest add mattpocock/skills --skill '*' --agent codex claude-code --global --yes`を実行し、その時点で上流に存在する全Skillを`~/.agents/skills`へ同期してClaude Codeへlinkします。既存Skillの更新だけでなく、新しく追加されたSkillも次回post-createで発見されます。これは再現性を優先する固定Pluginとは異なり、明示的に最新上流を購読する境界です。どちらも新しいセッションから利用できます。

## 共有repoをVS Codeへ表示する

Featureはconsumer repositoryの兄弟directory `../agent-repos`をcontainerの`/shared`へbind mountします。Dev Containerを開く前に、host側を次の構成にしてください。

```text
<projects>/
├── agent-repos/
│   ├── agent-config/
│   ├── shared-agent-plugins/
│   └── shared-devcontainer-features/
└── <consumer-project>/
```

VS Codeがcontainerへ接続するたびにFeatureの`postAttachCommand`が`code --add`を実行し、現在のprojectに加えて3つの共有repoを同じExplorerへ追加します。各consumerに`.code-workspace`や個別の`postAttachCommand`を置く必要はありません。

## Options

| option                       | default   | 説明                                                             |
| ---------------------------- | --------- | ---------------------------------------------------------------- |
| `installClaudeCode`          | `true`    | Claude Codeを導入する                                            |
| `installCodex`               | `true`    | Codex CLIを導入する                                              |
| `installSharedAgentPlugins`  | `true`    | Claude/Codexへ固定済み共通PluginとSkillを導入する                |
| `installMattPocockSkills`    | `true`    | post-create時にMatt Pocockの全Skillを両clientへ同期する          |
| `codexApprovalPolicy`        | `default` | Codex user設定を変更しないか、承認policyを明示する               |
| `codexSandboxMode`           | `default` | Codex user設定を変更しないか、sandbox modeを明示する             |
| `runDockerStorageGcOnCreate` | `false`   | 専用DinDへ接続するconsumerだけ、postCreate時の限定GCを有効化する |
| `installChromium`            | `true`    | `/usr/bin/chromium`を導入する                                    |
| `vercelVersion`              | `58.9.1`  | Vercel CLI version。`none`で導入しない                           |

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

## Docker storage safety

Featureの`devcontainer-docker-storage status`は、`DOCKER_HOST`、Docker context、daemon label、`docker system df`、`docker buildx du`を表示します。Docker-in-DockerとWindows Docker Desktop hostは別daemonなので、各環境で個別に計測してください。`gc`はBuildKit cacheを5GBへ制限し、`gc=ephemeral`ラベルがある未使用container/image/named volumeだけと、作成から7日超かつ現在未使用の`devcontainer.metadata` imageだけを削除します。実行中containerが参照するimageはDockerのpruneが保持します。Featureは共有host daemonのcache方針を暗黙に変えないよう、postCreate GCを既定では無効にしています。専用DinDを持つconsumerだけ`runDockerStorageGcOnCreate: true`を指定してください。

Windows hostでは[`scripts/windows/DevContainerDockerStorage.ps1`](scripts/windows/DevContainerDockerStorage.ps1)をPowerShellから実行します。

```powershell
.\scripts\windows\DevContainerDockerStorage.ps1 -Mode Status
.\scripts\windows\DevContainerDockerStorage.ps1 -Mode Gc
.\scripts\windows\Install-DevContainerDockerStorageGcTask.ps1
```

installerはDocker Desktopへログインしているユーザーのcontextで、毎日03:00に同じ限定GCを実行し、host BuildKit cacheを10GB以下に制限します。永続DB volumeには`gc=ephemeral`を付けず、E2Eなど再生成可能なvolumeだけに付けてください。Docker DesktopのDocker Engine設定はrepositoryから自動変更しません。Windows側で一度、Settings → Docker Engineに次をマージしてApply & Restartしてください。

```json
{
  "builder": {
    "gc": {
      "enabled": true,
      "defaultKeepStorage": "10GB"
    }
  }
}
```

これはhost Docker DesktopのBuildKit上限です。DinD側はconsumerが明示的に有効化したFeatureのpostCreate GCが5GBを保持するため、hostと混同しないでください。

## Release

Featureごとのversionは`src/<feature>/devcontainer-feature.json`の`version`で管理します。release前にversionをSemVerで更新し、`main`の`Test Features` workflowが成功することを確認してください。

1. GitHubのActionsから`Release Features` workflowを`main`に対して手動実行する。
2. workflow内の再検証とGHCR publishが成功したことを確認する。
3. 初回releaseではGitHub Packagesの`shared-devcontainer-features/web-dev`を`Public`へ変更する。repository自体はprivateのままでも構わない。
4. `ghcr.io/shnri/shared-devcontainer-features/web-dev:2`が認証なしでpullできることを確認する。

publish時に`3.1.0`、`3.1`、`3`、`latest`のOCI tagがFeature仕様に従って更新されます。Featureのソースとpackageに機密情報を含めないでください。

## このrepositoryを開発する

[`.devcontainer/devcontainer.json`](.devcontainer/devcontainer.json)にNode.js 24、Dev Container CLI 0.88.0、Docker-in-Dockerを用意しています。Dev Containerで開いた後、次のcommandでFeatureをbuild testできます。

```bash
devcontainer features test --features web-dev .
```

構成と配布方法は[Dev Container Feature仕様](https://containers.dev/implementors/features/)および公式[feature-starter](https://github.com/devcontainers/feature-starter)に準拠します。
