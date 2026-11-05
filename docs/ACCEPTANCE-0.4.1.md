# 0.4.1 — 本地凭据与可选 Keychain 验收

范围见 [PLAN-0.4.1.md](PLAN-0.4.1.md)。版本 **0.4.1 / build 6**；资料库 schema 4、Sparkle 更新签名身份不变。用户要求默认本地保存、Keychain 可选、同步发布新包并保留本机安装。

## 需求追踪

| 编号 | 实现与验证 |
| --- | --- |
| REQ/AC/TC-0411 | 缺少配置文件时默认 Local；升级不自动查询 Keychain，也不以 Keychain 作为本地读取失败的后备。模拟后端证明本地读写、删除、缺失凭据全部为零 Keychain 调用；应用自测验证公开 facade。 |
| REQ/AC/TC-0412 | 独立 Credentials 目录 0700、文件 0600；原子写入、文件锁与 actor 串行化。覆盖权限、重载、四个实例并发写入、格式损坏、未知 schema、文件容量、符号链接/硬链接、目录链接、命名管道和取消操作。异常不覆盖原内容。 |
| REQ/AC/TC-0413 | 通用设置可选 Local/Keychain；迁入 Keychain 先复制全部凭据再提交模式并移除本地值。复制失败保留完整本地状态，已写入 Keychain 的副本可保留。切回 Local 不访问 Keychain；会话缓存随文件 revision 变动失效。 |
| REQ/AC/TC-0414 | 导入只针对既有应用 service；逐项读密钥，全部成功才写入本地。已有本地值和主动删除记录优先；原 Keychain 不删除。覆盖部分读取后被拒、读取后任务取消、重新尝试、重复导入和仅本地模式可导入。 |
| REQ/AC/TC-0415 | 原 Canvas/模型账户标识和异步调用接口保留；自动整理与 token 维护在切换时取消后重启。凭据不进入课程归档和 WebKit snapshot。后台缺失 Canvas token 为非模态提示，显式同步仍提示配置。 |
| REQ/AC/TC-0416 | 中英浅深色设置、错误和更新区域已用真实活动窗口检查；源码/包/feed 的公开发布核验见下方交付记录。本机安装保留供用户测试更新。 |

## 已执行验证

证据在 `build/verification/0.4.1/`，不随公开仓库提交；测试和截图脚本可以重跑。

| 检查 | 结果 | 证据 |
| --- | --- | --- |
| Swift Testing | **215 项 / 22 套件通过**；新增 18 项凭据测试，含参数化输入 | `tests-final.log` |
| Web | **22 项通过**；lint、TypeScript、Vite 构建通过，无前端业务改动 | `web-tests.log`、`web-lint.log`、`build-final.log` |
| 实际应用自测 | **72 项通过**；包括本地 facade、账户隔离、归档/WebKit 不含凭据、空凭据集模式切换、后台/显式同步缺失 token 的不同提示及现有工作区交互 | `selftest-final.log` |
| 真实窗口 | **24 张**：中英各 12 张；Local、Keychain、取消授权、更新区域、Canvas、Models 各浅深色 | `settings/`、`snapshots.log` |
| 布局 | 网格 lint 通过；逐张审阅设置文本、对齐、换行和滚动后的更新区，未发现阻断 | `grid.log`；四份 contact 图及原始截图 |
| Release 构建 | arm64 Release、离线 Web 资源和嵌套 ad hoc 签名通过 | `build-final.log` |

设置截图使用隔离 Demo，凭据按钮和网络操作保持禁用；Keychain/错误状态为显示 fixture，不声称真实系统授权弹窗已演练。截图均满足活动窗口条件，无 view-render fallback。原生 Form 由系统布局，24 份记录没有自定义探针，不据此声称已自动测量每个表单控件；视觉审阅负责此部分。最终补充的非普通文件拒绝检查不改变 UI，随后重建并重跑应用自测。

Swift 编译无 warning。Vite 仍提示上游 ReUI 的 `use no memo` 指令被忽略、对应 source-map 定位及单脚本体积；这是既有提示，离线 WKWebView 实际加载与交互通过。初次新增截图 fixture 使用了模块内初始化器，已改为本地化显示 fixture 并重新编译通过；不把初次失败记为通过。

## 证据评分

| 维度 | 分数 | 边界 |
| --- | --- | --- |
| 需求与验收覆盖 | 25/25 | 六项要求均有实现和验证路径 |
| 功能正确性与边界 | 24/25 | 模式、迁移、失败回滚、并发及文件边界均回归；未演练每种 macOS Keychain ACL |
| 测试充分性与结果 | 18/20 | 自动化与真实窗口通过；未读取用户真实凭据或实测系统 Keychain 导入、自然更新安装 |
| 架构、接口与扩展性 | 10/10 | 统一异步 facade、独立 actor/文件/backend，UI 无秘密值 |
| 代码质量、安全与维护 | 9/10 | 所选明文存储的权限与限制已准确说明；没有独立安全审计或掉电故障注入 |
| 文档与交付完整性 | 10/10 | 双语说明、tag、四个发布附件、公开回读和本机安装保留证据完整 |
| **合计** | **96/100** | **实现与公开交付完成；本机更新过程保留给用户验证。** |

## 交付记录

- [v0.4.1](https://github.com/yangbo-s/Syllapace/releases/tag/v0.4.1) 已公开为 latest，非 prerelease；版本 0.4.1/build 6。源码和 tag 对应 `a7d45bb`，均已推送。
- 最终包来自 `build/releases/0.4.1-final/`；`build/releases/0.4.1/` 是未发布候选，不用于本轮交付。最终 ZIP 5,263,376 字节，DMG 5,191,507 字节；另含 `appcast.xml` 和 `SHA256SUMS`。
- 草稿四个附件的上传状态、大小和 GitHub SHA-256 与本地完全匹配后公开。随后从公开无鉴权地址重新下载全部附件，内容匹配；固定 latest feed 与本地 appcast 完全一致。
- 公开 ZIP 通过 SHA-256、包内公钥 Ed25519、应用嵌套签名、版本与架构检查；DMG 完整性通过。只读挂载公开 DMG 后，比对 Info.plist 和应用二进制均与最终构建相同，签名有效，验证后已卸载。证据：`package-final.log`、`draft-verify.log`、`public-verify.log`。
- 公开回读文件位于 `/tmp/syllapace-041-public-w02jfee4/`，临时验证脚本已清理。系统对旧 hdiutil attach/detach 命令形式给出弃用提示；本次挂载、检查与卸载均成功。
- `/Users/muse/Applications/Syllapace.app` 保持 **0.4.0 (5)**；Info.plist 和二进制 SHA-256 均与开工基线相同，Sparkle 公钥与新包一致。本轮没有替换、启动或退出该正式安装，没有改变其更新偏好或计时。应用内自然检查、安装与重启未代用户执行。
- 发布前证据评分为 95/100，公开交付验证后交付维度加 1 分，最终 **96/100**。

## 明确边界

本次不读取或迁移用户真实 Canvas/model 凭据；Keychain 系统服务的读取/写入仍使用既有 Security.framework API，新导入的枚举/复制逻辑以模拟后端验证。可选 Keychain 模式仍可能要求授权。默认本地文件不是加密保险库，同一系统账户下的程序可读取；应用不会自动清除原 Keychain 记录，也不保证安全擦除磁盘旧块。

真实 Canvas/模型网络协议未修改，不以本次合成凭据自测声称重新验证用户账号连通性。用户本机自然 Sparkle 检查、安装和重启留给用户验证；公开包校验不能替代这些结果。应用仍未进行 Apple Developer ID 签名或公证。
