# GitHub Release 发布

发布目标是 `yangbo-s/Syllapace`。安装包通过 GitHub Release 托管；应用固定读取 `https://github.com/yangbo-s/Syllapace/releases/latest/download/appcast.xml`。因此公开发行使用正常 Release，并将经过验证的版本设为 latest；GitHub prerelease 不作为当前更新源。

## 每次应用交付的完成条件

遵循根目录 [AGENTS.md](../AGENTS.md) 的交付约定。源码/tag、版本与 build、DMG/ZIP、签名 appcast、公开 latest 必须一致；从公开下载地址回读验证后，才报告应用修订已交付。不能只推送源码而留下旧安装包。

自动验证运行仓库构建或隔离副本。本机正式安装由用户自行验证更新；发布前后只读核对其版本和文件指纹，保留用户的更新偏好、上次检查时间和资料。没有实际执行更新时，验收记录只能写“公开更新源及包校验通过”，不能写成“本机跨版本升级通过”。

当前启用自动检查，采用 Sparkle 默认约 24 小时检查间隔；应用需运行，检测到新版后由用户确认安装。发布到 GitHub 不会立即向客户端推送，手动“检查更新”可立即发起检查。测试自然调度时保留客户端的真实检查时间，不用修改计时或偏好来制造通过。

## 发布输入与产物

`Info.plist` 是版本、最低系统版本、更新 URL 和 Ed25519 公钥的来源。每次更新递增 `CFBundleVersion`，同时更新 `CFBundleShortVersionString` 与对应的 `docs/releases/<version>.md`。当前构建目标为 Apple Silicon、macOS 26.0+。

`tools/package_release.sh [新输出目录]` 只处理已构建的 `build/Syllapace.app`，不联网发布，不生成或导出私钥，也不覆盖已有输出目录。默认输出到 `build/releases/<version>/`：

| 产物 | 用途 |
| --- | --- |
| `Syllapace-<version>-macOS-arm64.dmg` | 只读 APFS/LZFSE 安装镜像，内含应用与 Applications 链接 |
| `Syllapace-<version>-macOS-arm64.zip` | 使用 ditto 保留 framework 符号链接的应用归档；Sparkle 更新包 |
| `appcast.xml` | 版本、build、macOS/arm64 约束、不可变版本下载 URL、长度和 Ed25519 签名 |
| `SHA256SUMS` | ZIP、DMG、appcast 的 SHA-256 校验值 |

包内包含 `Contents/Resources/THIRD_PARTY_NOTICES.md` 及 Sparkle framework 自带资源。0.4.0 起，离线工作区位于 `Contents/Resources/Workspace/`，其 `THIRD_PARTY_NOTICES.txt` 收录 ReUI 和实际运行依赖的许可证。不要将测试资料库、开发 fixture、用户资料、凭据、签名私钥、source map 或临时诊断文件放入安装包。

## 更新签名

Sparkle 2.10.1 的工具由 SPM 放在 `.build/artifacts/sparkle/Sparkle/bin/`。可用 `SPARKLE_BIN` 指定其他同版本工具路径。更新签名使用登录 Keychain 中 account 为 `app.syllapace.mac` 的既有密钥；可通过 `SPARKLE_KEYCHAIN_ACCOUNT` 指定明确的其他账户。发布机需要能够读取该密钥。

首次建立更新身份由维护者单独执行 Sparkle `generate_keys --account app.syllapace.mac`，把返回的**公钥**写入 `Info.plist` 的 `SUPublicEDKey`。私钥留在 Keychain，不进入仓库、环境变量、日志或 Release。后续版本继续使用同一密钥。没有 Developer ID 身份时，丢失这把密钥会阻断现有安装的可信更新链；维护者应妥善保留 Keychain 恢复能力。

应用启用 `SUVerifyUpdateBeforeExtraction`，更新包需通过签名验证后才能解压。当前 appcast 通过 GitHub HTTPS 提供，未启用独立 feed 签名。签名证明 ZIP 来自持有更新私钥的发布者；它不等于 Apple Developer ID 签名或公证。

## 构建、校验与上传

在根目录执行：

```sh
./tools/test.sh
./build.sh --release
./tools/selftest.sh
./tools/package_release.sh
```

0.4.0 起构建机还需 Node.js 22.12+ 与 npm。`build.sh` 调用 `tools/build_workspace.sh`，按 `Web/package-lock.json` 安装依赖并构建工作区，再将静态产物复制进应用后签名；最终应用不需要 Node.js 或本地服务器。前端行为检查在 `Web/` 执行 `npm test`、`npm run lint`，类型检查随构建执行。不要在测试或构建使用 `node_modules` 时并发运行 `npm ci`。

工作区通过 `file://` 在 WKWebView 加载，产物必须为 classic IIFE + `defer`，本地 JS/CSS 标签不能使用 `crossorigin`。保留严格 CSP，不以允许远程脚本或任意网络连接修复加载失败。postbuild 与发布校验检查离线资源、许可证和开发 fixture；应用自测还需确认实际 React 渲染及原生消息回写，不能用文件存在代替运行验证。

中英文浅深色真实窗口、语言切换和更新流程需另外检查。打包器校验应用签名、arm64、更新配置、版本，生成签名后用 CryptoKit 对照**包内公钥**验证 ZIP，再解压复核 app 签名并检查 DMG 完整性。已有产物可独立重验：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  python3 tools/verify_release.py verify build/releases/0.1.0
```

复核 Git 差异和验收记录，提交并推送源码，然后创建对应 tag。先创建 GitHub draft，上传完整附件，确认内容后再公开，避免用户看到缺少 appcast 或安装包的 Release。例如首发：

```sh
git tag v0.1.0
git push origin main v0.1.0
gh release create v0.1.0 --repo yangbo-s/Syllapace --verify-tag --draft \
  --title 'Syllapace 0.1.0' --notes-file docs/releases/0.1.0.md \
  build/releases/0.1.0/Syllapace-0.1.0-macOS-arm64.dmg \
  build/releases/0.1.0/Syllapace-0.1.0-macOS-arm64.zip \
  build/releases/0.1.0/appcast.xml build/releases/0.1.0/SHA256SUMS
gh release edit v0.1.0 --repo yangbo-s/Syllapace --draft=false --latest
```

草稿附件校验从 GitHub releases 列表中按 `tag_name` 定位并读取其 ID；按 tag 直接查询未发布草稿可能返回 404。公开后重新读取正式 Release 元数据中的下载 URL，草稿阶段的 `untagged-*` 临时地址不能用于公开回读。确认四个 asset 的状态、长度与 GitHub 返回的 SHA-256 都匹配本地产物后再公开。

不要覆盖已公开版本的二进制。需要修正可执行文件时递增版本和 build 并发布新 Release。发布后从 GitHub 下载附件到新的临时目录，重验哈希、Ed25519 签名、解压后 app 签名和版本；核对 latest URL 可用。用户本机的检查、下载安装与重启留给用户测试；需要额外端到端自动验证时使用隔离副本，并在验收记录中说明测试条件。

## 首发签名状态

0.1.0 使用 ad hoc 应用签名，尚未进行 Apple Developer ID 签名或公证。发布说明应保留这一事实及 [Apple 官方的单应用打开流程](https://support.apple.com/en-us/102445)，不提供关闭 Gatekeeper 或批量删除 quarantine 的命令。

日后引入 Developer ID 时，先完成嵌套 framework/helper 签名、Hardened Runtime、公证与 stapling 验证，再更新发布说明；不得只设置 `SIGN_IDENTITY` 就宣称完成公证。

规范依据：[Sparkle 集成](https://sparkle-project.org/documentation/)、[Sparkle 发布与签名](https://sparkle-project.org/documentation/publishing/)。
