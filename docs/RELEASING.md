# GitHub Release 发布

发布目标是 `yangbo-s/Syllapace`。安装包通过 GitHub Release 托管；应用固定读取 `https://github.com/yangbo-s/Syllapace/releases/latest/download/appcast.xml`。因此公开发行使用正常 Release，并将经过验证的版本设为 latest；GitHub prerelease 不作为当前更新源。

## 发布输入与产物

`Info.plist` 是版本、最低系统版本、更新 URL 和 Ed25519 公钥的来源。每次更新递增 `CFBundleVersion`，同时更新 `CFBundleShortVersionString` 与对应的 `docs/releases/<version>.md`。当前构建目标为 Apple Silicon、macOS 26.0+。

`tools/package_release.sh [新输出目录]` 只处理已构建的 `build/Syllapace.app`，不联网发布，不生成或导出私钥，也不覆盖已有输出目录。默认输出到 `build/releases/<version>/`：

| 产物 | 用途 |
| --- | --- |
| `Syllapace-<version>-macOS-arm64.dmg` | 只读 APFS/LZFSE 安装镜像，内含应用与 Applications 链接 |
| `Syllapace-<version>-macOS-arm64.zip` | 使用 ditto 保留 framework 符号链接的应用归档；Sparkle 更新包 |
| `appcast.xml` | 版本、build、macOS/arm64 约束、不可变版本下载 URL、长度和 Ed25519 签名 |
| `SHA256SUMS` | ZIP、DMG、appcast 的 SHA-256 校验值 |

包内包含 `Contents/Resources/THIRD_PARTY_NOTICES.md` 及 Sparkle framework 自带资源。不要将测试资料库、用户资料、凭据、签名私钥或临时诊断文件放入安装包。

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

不要覆盖已公开版本的二进制。需要修正可执行文件时递增版本和 build 并发布新 Release。发布后从 GitHub 下载附件到新的临时目录，重验哈希、Ed25519 签名、解压后 app 签名和版本；核对 latest URL 可用，并在已安装应用中执行「检查更新」。首发没有已公开的旧版本，完整跨版本安装验证需要用隔离的测试副本进行，并在验收记录中说明测试条件。

## 首发签名状态

0.1.0 使用 ad hoc 应用签名，尚未进行 Apple Developer ID 签名或公证。发布说明应保留这一事实及 [Apple 官方的单应用打开流程](https://support.apple.com/en-us/102445)，不提供关闭 Gatekeeper 或批量删除 quarantine 的命令。

日后引入 Developer ID 时，先完成嵌套 framework/helper 签名、Hardened Runtime、公证与 stapling 验证，再更新发布说明；不得只设置 `SIGN_IDENTITY` 就宣称完成公证。

规范依据：[Sparkle 集成](https://sparkle-project.org/documentation/)、[Sparkle 发布与签名](https://sparkle-project.org/documentation/publishing/)。
