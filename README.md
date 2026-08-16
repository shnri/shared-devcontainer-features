# shared-devcontainer-features

Webプロジェクトで共通利用するDev Container Featureです。各projectはこのrepositoryをGit submoduleとして固定し、`image`やworkspace設定などの入口だけを持ちます。Node.js、Python、AI開発CLI、ブラウザなどの共通toolchainはlocal `web-dev` Featureから追加します。

## 利用方法

### `.devcontainer`全体をsubmoduleにする

project固有のDev Container設定が不要な場合は、このrepository自体を`.devcontainer`として追加できます。rootの`devcontainer.json`がlocal `web-dev` Featureを参照します。

```bash
git submodule add https://github.com/shnri/shared-devcontainer-features.git .devcontainer
```

この場合、VS Codeが読むpathは`.devcontainer/devcontainer.json`です。新しくcloneした後は、Dev Containerを開く前にsubmoduleを初期化してください。

### project固有の設定を残す

volume、workspace、lifecycle commandなどをproject側で変更する場合は、共有repositoryを`.devcontainer`配下のsubdirectoryへ追加します。

まずconsumer repositoryへsubmoduleを追加します。

```bash
git submodule add https://github.com/shnri/shared-devcontainer-features.git .devcontainer/shared-devcontainer-features
```

既存consumerを新しくcloneするときは、Dev Containerを開く前にsubmoduleを初期化します。local Featureはcontainer作成前に読み込まれるため、project側の`postCreateCommand`だけでは初回初期化できません。

```bash
git clone --recurse-submodules <consumer-repository-url>
# またはclone後に
git submodule update --init --recursive
```

`.devcontainer/devcontainer.json`から、`devcontainer.json`を基準とした相対pathでFeatureを参照します。

```jsonc
{
  "name": "my-web-project",
  "image": "mcr.microsoft.com/devcontainers/base:2.1.13-bookworm",
  "features": {
    "./shared-devcontainer-features/src/web-dev": {},
  },
}
```

Dev Container CLIはlocal Featureを`.devcontainer/`配下からだけ読み込むため、submoduleもこのdirectory内へ配置します。

このFeatureはDebian Bookworm系のDev Container imageと、標準の`vscode` user（homeは`/home/vscode`）を対象にしています。

## 含まれるもの

- Node.js 24、npm、pnpm 11.22.0
- Python 3.12、SkillSpector 2.8.2相当（commit固定）
- GitHub CLI
- Chromium、Vercel CLI 58.9.1
- Claude Code 2.1.233、Codex 0.147.0
- Claude Code/CodexのVS Code extension
- Claude/Codexの認証・設定を保持するproject別named volume

Claude CodeとCodexはremote user所有にするため、container作成後に公式standalone installerで導入します。versionを更新する場合はFeature optionを変更するか、このrepositoryで既定値を更新し、CI成功後にconsumerのsubmodule固定commitを進めてください。

## Options

| option                | default   | 説明                                                 |
| --------------------- | --------- | ---------------------------------------------------- |
| `installClaudeCode`   | `true`    | Claude Codeを導入する                                |
| `claudeCodeVersion`   | `2.1.233` | `stable`、`latest`、またはversion                    |
| `installCodex`        | `true`    | Codex CLIを導入する                                  |
| `codexVersion`        | `0.147.0` | `latest`、またはversion                              |
| `codexApprovalPolicy` | `default` | Codex user設定を変更しないか、承認policyを明示する   |
| `codexSandboxMode`    | `default` | Codex user設定を変更しないか、sandbox modeを明示する |
| `installChromium`     | `true`    | `/usr/bin/chromium`を導入する                        |
| `vercelVersion`       | `58.9.1`  | Vercel CLI version。`none`で導入しない               |

`codexApprovalPolicy`と`codexSandboxMode`の既定値は`default`です。Featureはconsumerの安全設定を暗黙に弱めません。Dev Container自体を外側の隔離境界として扱うprojectだけが、例えば次のように明示します。

```jsonc
"./shared-devcontainer-features/src/web-dev": {
  "codexApprovalPolicy": "never",
  "codexSandboxMode": "danger-full-access"
}
```

## 既存volumeを維持するconsumer

Featureの既定volume sourceには`${devcontainerId}`が含まれ、projectごとに分離されます。既存projectが別名のvolumeを使用中なら、同じtargetを`devcontainer.json`側で指定するとlocal設定が優先されます。

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

## 更新

共有設定を変更するときは、このrepositoryのpull requestでCIを通してmainへmergeします。consumerは明示的にsubmoduleの固定commitを進め、同じ変更でDev Containerをrebuildします。

```bash
git -C .devcontainer/shared-devcontainer-features fetch origin main
git -C .devcontainer/shared-devcontainer-features checkout <adopted-commit>
git add .devcontainer/shared-devcontainer-features
```

各consumerが固定commitを更新するまで環境は変わりません。GHCRへのpublishや、project間でのfile copyは行いません。

## このrepositoryを開発する

rootの[`devcontainer.json`](devcontainer.json)は、consumerの`.devcontainer/devcontainer.json`として使用するentrypointです。repository単体でFeatureをtestする場合は、Dev Container CLIとDockerを用意して次のcommandを実行します。

```bash
devcontainer features test --features web-dev .
```

構成と配布方法は[Dev Container Feature仕様](https://containers.dev/implementors/features/)および公式[feature-starter](https://github.com/devcontainers/feature-starter)に準拠します。
