# 实施与验收记录

日期：2026-11-04。范围见 [ENGINEERING.md](ENGINEERING.md)。本记录区分实现、自动化证据和真实外部联调，不能用单元测试替代账户与系统权限验收。

## 当前结果

0.2.0 (3) 的学期范围、Canvas 来源扩展与连接修复已实现并公开发布，安装包与 latest 更新 feed 的公开回读验证通过。本轮完整测试 **100 项 / 12 套件**、应用自测 **16 项**通过；真实 Canvas 只读连接、token 唯一识别和配置模型的合成日期提取均通过。真实 PAT 到期延长、本机自然更新及 EventKit 权限/写入仍未实测。最新追踪、证据和评分见文末「0.2.0 学期与来源修复交付」，下方早期结果保留为历史记录。

## 0.1.x 实施基线（历史）

原生 macOS 应用、核心数据处理、Canvas/BYOK 适配、桌面卡片与 EventKit 适配已实现。当前源码新增 Canvas token 自动续期与空状态居中修复，完整项目的 **69 项 Swift Testing 测试、9 个测试套件通过**；应用自测的 **9 项检查通过**。Release 构建成功，所查本轮测试与构建日志没有 Swift 编译警告。首发时的 Debug 构建和版本验收另见历史记录。

真实 Canvas 账户、BYOK 服务和用户授权后的 EventKit 读写尚未运行。浅深色窗口截图、窄窗口及空状态已完成阅图；修正后的网格检查通过。真实 UI 点击与快捷键流程已检查。**当前不是全部 P0/P1 验收通过的正式发布结论。**

环境：arm64 macOS 27.0.1，Xcode 提供 Swift 6.4.2，项目目标 macOS 26+、Swift 6 模式。macOS 26 最低版本运行兼容性尚未单独实测。

## 执行证据

| 检查 | 实际结果 | 证据 |
| --- | --- | --- |
| `./tools/test.sh` | 69/69 通过，9 套件 | 本轮日志 `/tmp/syllapace-token-tests.log`；测试源码见下表及续期增量记录 |
| `./tools/selftest.sh` | 9/9 通过，`SELFTEST complete` | `/tmp/syllapace-token-selftest.log`；`Sources/Syllapace/SelfTest.swift` |
| Debug 构建 | 通过，生成 `.app` | `/tmp/syllapace-build-final.log` |
| Release 构建 | 通过，生成并签名 `.app` | `/tmp/syllapace-token-build.log` |
| `./tools/snap.sh` | 最终捕获成功；主页面、编辑/导入、桌面卡片和三项设置两色均已阅图 | `/tmp/syllapace-snap-final.log`；`.impeccable/review/` |
| `./tools/grid-lint.sh` | 修正后 PASS；运行时布局检查也通过（23 份 JSON，其中 17 份有自定义布局探针，6 份为系统 Form 设置页） | `/tmp/syllapace-grid.log`、`/tmp/syllapace-layout-check.log`、`.impeccable/review/*-layout.json` |
| Canvas/BYOK 真实请求 | 未运行 | 没有用户账户凭据或 API key |
| EventKit 授权及真实 Calendar 写入 | 未运行 | 本轮没有请求用户日历权限或创建真实日历 |

`/tmp` 日志是本次工作环境中的证据路径，不是仓库随附产物，可能被系统清理。以上脚本可重新生成相应验证结果。

## 需求追踪与测试用例

| 需求 / 验收 | 实现 | 测试 / 观察证据 | 状态与边界 |
| --- | --- | --- | --- |
| REQ-001 / AC-001 原生应用 | `Package.swift`、`build.sh`、`Sources/Syllapace/App.swift`、`ContentView.swift`、`Theme.swift` | TC-001：Debug/Release 构建通过；示例与空状态快照 | 构建与界面阅图通过；最低系统版本实机未测 |
| REQ-002 / AC-002 Canvas | `Sources/SyllapaceKit/CanvasClient.swift`、`CredentialStore.swift`、`Sources/Syllapace/SettingsView.swift` | TC-002：`rejectsCredentialBearingOrNonHTTPSHosts`、`paginationCannotEscapeOriginOrEndpoint`、`partialFailuresPreserveSuccessfulCourseAssignments`、`binaryRedirectNeverForwardsBearer`、`downloadRejectsPrivateRedirect`、`canvasAllDayDateUsesCourseTimeZone` | 模拟契约通过；真实机构权限、token 与 Keychain 运行流程未联调 |
| REQ-003 / AC-003 文档 | `Sources/SyllapaceKit/DocumentReader.swift` | TC-003：`pdfRetainsPageReferences`、`docxTablesKeepCellAssociation`、`localIdentitySurvivesContentRevision`、`malformedPDFIsRejected`、`oversizedTextFailsWithoutReadingUnlimitedContent` | 合成 PDF/DOCX、错误和大小边界通过；复杂真实排版未评估 |
| REQ-004 / AC-004 提取审核 | `Extraction.swift`、`LLMClient.swift`、`Reconciliation.swift`、`Sources/Syllapace/Editors.swift`、`AppModel.swift` | TC-004：`ambiguousNumericDateStaysUnresolved`、`releaseAndDueDatesAreNotConflated`、`nonexistentDSTTimeIsNotInvented`、`repeatedDSTTimeNeedsReview`、`modelOutputRequiresActualSourceEvidence`、`modelRejectsInvalidDatesAndExtraInstructions`、`modelRequestIsToolFreeAndBounded`、`truncatedModelOutputIsNotAccepted`；应用自测导入/批准/重复/改期 | 自动化通过；提取准确率与真实模型效果未测量 |
| REQ-005 / AC-005 日程及离线 | `Sources/Syllapace/AppModel.swift`、`ContentView.swift`、`EventDisplay.swift`、`Sources/SyllapaceKit/ArchiveStore.swift` | TC-005：`saveLoadAndBackup`、`corruptionNeverOverwritesBackup`、`unknownSchemaIsRejected`、`userOverrideDoesNotConflictWithUnchangedSource`；应用自测重载一致 | 持久化和冲突逻辑通过；搜索、课程过滤、完成切换和候选批准已通过真实 UI 操作 |
| REQ-006 / AC-006 桌面卡片 | `Sources/Syllapace/DesktopPanel.swift` | TC-006：`desktop-light.png`、`desktop-dark.png`；实际置顶切换、关闭主窗口后点击桌面事件重开对应详情通过；拖拽未单独验收 | 显示和核心交互通过；不是 WidgetKit，尚未做完整 Spaces/Mission Control 兼容验收 |
| REQ-007 / AC-007 EventKit | `Sources/SyllapaceKit/CalendarSyncPlanner.swift`、`Sources/Syllapace/CalendarBridge.swift` | TC-007：`stableRepeatedSyncDoesNotCreateDuplicate`、`movesOriginalEventWhenDateChanges`、`preservesExternalEditAndDeletion`、`relinksIdentifierWithoutChangingIdentity`、`recoversCommittedWriteAfterMappingFailure`、`recoversInterruptedDelete`、`rejectsOnlyOwnedUnmodifiedEvent`、`floatingDateSurvivesDeviceTimeZoneDifference` | 纯同步规划器通过；系统授权、实际写入、失败恢复仍需真实环境验收 |
| REQ-008 / AC-008 ICS | `Sources/SyllapaceKit/ICSExporter.swift` | TC-008：`allDayUsesExclusiveNextDateAndStableUID`、`unconfirmedEventsAreExcludedAndInjectionIsEscaped`、`unicodeFoldingUsesOctets` | 序列化测试通过；Apple/Google/Outlook 实际导入互操作未测试 |

测试名称位于 `Tests/SyllapaceKitTests/CoreTests.swift`、`ConnectorTests.swift`、`CalendarSyncTests.swift`。TC-001/006 属于构建与界面验收，其余为单元/模块/模拟契约测试；应用自测覆盖模块间真实调用但使用合成数据及临时存储。

## 已知行为与边界

- 日期未知或歧义时保留候选。人工编辑与来源观测分开保存；再次同步同一来源不反复覆盖用户决定。跨来源相似标题只提示冲突，不自动证明事件等价。
- Canvas 同步按课程保留成功结果；访问失败与来源暂时缺项不会删除旧事件。自动刷新须主动启用，且仅在应用运行期间执行。
- 自动发现的是大纲 HTML 与疑似课程文件元数据。PDF/DOCX 由用户选择下载；文件版本变化需要再次导入，没有后台遍历并重新下载全部附件。
- BYOK 是兼容 chat completions 的 HTTPS 适配器，有输入/输出限制与严格响应校验。模型没有工具；证据匹配仍不能保证解释正确，用户需要审核。
- Calendar 当前仅使用本地 `On My Mac` 来源。完整日历访问是系统权限范围，专用日历和事件归属限制由应用逻辑实施。外部编辑/删除保留为冲突，只有用户确认“Use Syllapace version”才替换或重建；不提供反向导入。
- 应用退出后不会继续拉取 Canvas 或模型数据。已保存到 Calendar 的事件由系统保留。
- 扫描 PDF/OCR、多语种规则完整覆盖、Windows、其他 LMS、后台代理、OAuth、iCloud 目标选择均未实现。
- 本地归档采用原子 JSON + 上次有效备份；不是应用级加密数据库。构建产物默认 ad hoc 签名，未公证。

## 首发前完整产品证据评分（历史基线）

以下保留首发前实现及当时验证证据的评分；后续增量单独记录，避免将局部验证当成完整产品复验。真实外部联调缺失单列为验收边界。独立视觉审阅为 94/100，仅代表当时截图与交互范围，不替代功能验收。

| 维度 | 得分 | 证据、扣分及后续验证 |
| --- | --- | --- |
| 需求与验收覆盖 | 22/25 | 八项需求均有实现入口；界面与核心交互验证完成，账户接入和系统日历权限尚未闭环 |
| 功能正确性与边界处理 | 21/25 | 日期/重复/冲突/存储/连接器/日历规划器测试通过；实际端到端外部行为未验证 |
| 测试充分性与结果 | 17/20 | 完整项目 54 项测试 + 9 项应用自测及真实 UI 冒烟检查通过；缺少真实外部联调、Calendar 客户端导入及代表性大纲评估 |
| 架构、接口与扩展性 | 9/10 | Kit 与 UI/系统适配分层，稳定来源/事件ID，观测与人工状态分离；JSON 存储适合当前规模，迁移只拒绝未知版本 |
| 代码质量、安全性、可维护性 | 9/10 | Swift 6 构建无编译警告、凭据Keychain、同源请求与下载重定向限制、文档资源边界；未完成独立安全审计和真实权限检查 |
| 文档与交付完整性 | 10/10 | 构建/演示/测试脚本、示例、README、决策、设计规范和验收记录齐备；真实窗口证据已生成 |
| **总分** | **88/100** | **可供本机试用和继续验证；尚不能宣布所有 P0/P1 已通过。** |

## 最终界面与交互证据

- 真实窗口截图：Today、Timeline、Review、Sources、事件编辑、导入、桌面卡片、Settings 的 Canvas/Extraction/Calendar 三页，各有浅色与深色版本；另有搜索空状态、初始空状态、940pt 宽窗口。
- 修正并重新捕获：浅色警告文字、深色主按钮对比度、日期带前景色、编辑/导入初始焦点、空状态行动位置及搜索无结果文案。独立视觉审阅结论为通过，本轮发现的问题全部关闭。
- CUA 实际操作：搜索无结果与清空、⌘N 新建、回车保存、完成/未完成切换、⌘O 打开及 Esc 取消、课程过滤、候选批准使待审计数从 3 减至 2、来源原文阅读及 Esc 关闭、桌面卡片置顶切换、关闭主窗口后通过卡片事件重开对应详情。全部使用明确标记的临时演示空间。
- `.impeccable/review/settings-dark.png` 是旧轮次遗留，已删除；证据采用 `settings-{0,1,2}-{light,dark}.png`。截图与编译资源属于可重新生成的本地产物，不提交至 Git。
- 运行时布局探针按实际 NSWindow 坐标记录，仅测可见自定义内容，防止主窗口、sheet 与桌面窗口坐标混用；对齐、内边距、边界、间距及重叠断言通过。系统 Form/Sidebar/Toolbar 不重复测量。
- 用户选定 C「课程卡片」后，进一步统一全图几何：纸张/内容/端点圆角为 R32/R16/R8；前后页等量偏移，直段和转角主体间距 32；内容四边相对页矩形留白 96，标题和日期格间距均为 64；翻角 R96/R128 同心并以 R8 相切收口。`python3 tools/make_brand.py --check` 的 20 项几何与导出检查通过，10 个生成文件与参数一致；实际日期圆到翻角净距 34.274170 ≥ 32。端头收圆处间距自然展开，不计作恒宽 32。
- 透明 SVG、四色变体、可再生成参数及结构图见 `Brand/`；原生分层源见 `Icon/AppIcon.icon/`。四种原生外观及 32pt 预览已阅图且独立复核通过，日期圆与翻角仍分离；真实 16px 仅以叠页主轮廓为通过依据，不承诺圆环、圆心、各日期格分别清晰。证据为 `/tmp/syllapace-icon-v3.png`、`/tmp/syllapace-icon-v3-16px.png` 与 `Brand/concepts-v2/alignment.png`。
- 上一轮图标修订仅修改品牌资产及其生成和说明文件。Release 构建、安装包签名验证通过，已在 `/Users/muse/Applications/Syllapace.app` 的真实 About 窗口核验新图标。应用逻辑未改变，未重复运行原有 49 项测试与 7 项自测。未进行完整 VoiceOver、窗口拖拽、多显示器/Spaces、长时间性能与真实权限交互验收。

## 仍待真实环境验证

用户自行配置后的 Canvas、BYOK、EventKit 实测；机构权限、模型兼容性、系统授权与外部日历修改/恢复需逐项核验。凭据只在应用中输入，不写入仓库、日志、截图或测试夹具。


## 0.1.0 中英文、更新与首发验证

本轮范围为 REQ-009—011。新增 251 个中英词条、原生语言选择、Sparkle 2.10.1 与 GitHub Release 更新、可重复打包及验证脚本。课程、证据、归档数据和 Canvas 等术语不翻译。首发支持 macOS 26+、Apple Silicon，ad hoc 签名且未公证。

| 验收 / 用例 | 已执行结果及证据 |
| --- | --- |
| AC-009 / TC-009 | 5 项新增语言测试包含系统回退、术语保留、资源键及占位符一致性、中文参数顺序和用户内容不变。全套54测试/8 suites通过；应用9项自测通过，已验证包内语言资源。 |
| AC-009 / 真实交互 | Settings 中英来回切换后主窗口、菜单操作与控件标签更新；重启后保留简体中文。未保存标题 `Draft kept across languages 42` 与关闭“仅日期”的选择都保留；课程/类型选中值正确切换。修复过根View重建丢草稿，以及Form控件重复ID导致互相替换的问题。 |
| AC-009 / 视觉 | `/tmp/syllapace-0.1.0-shots/{en,zh-Hans}`：50张浅深色主界面、设置、编辑/导入、桌面卡片及空/窄窗口图，独立阅图无阻断问题；网格检查通过。最终控件修订后刷新同一路径。 |
| AC-010 / TC-010 | 更新菜单/Settings按钮实际可用；未发布feed时显示可恢复错误。隔离副本0.0.0→0.1.0经历发现、下载、签名校验、替换、重启；原测试课程与日程仍可见，签名验证通过。测试独立bundle ID及LSEnvironment固定临时资料库，未替换用户安装。 |
| AC-010 / 错误边界 | 对测试ZIP追加字节但保留原签名，Sparkle实际报告“improperly signed”并拒绝安装；副本保持build1。测试HTTP仅绑定127.0.0.1且已停止；生产使用HTTPS GitHub。demo/selftest/snapshot不能启动更新。 |
| AC-011 / TC-011 | Release构建无Swift警告；ZIP解包后完整签名通过；CryptoKit用包内公钥验证Ed25519；DMG完整性和SHA256匹配。日志 `/tmp/syllapace-0.1.0-package-final.log`，附件 `build/releases/0.1.0-final/`。公开发布后四个附件均已重新下载，SHA256、包内公钥签名、ZIP签名及DMG完整性通过；latest/feed重定向正确。 |

本轮范围证据评分：需求与验收覆盖24/25、行为与边界24/25、验证18/20、架构与接口10/10、维护与安全9/10、文档交付9/10，合计 **94/100**。扣分边界：未在最低macOS26机器实测、未覆盖长时间自动更新调度与系统权限拒绝的所有组合、缺Developer ID公证；公开下载回读已经通过。本分数针对本轮语言/更新/打包，不替代上方完整产品88分及真实服务未联调的边界。


### 公开发布后核验

- 已公开：[v0.1.0](https://github.com/yangbo-s/Syllapace/releases/tag/v0.1.0)，tag对应源码提交 `f3ff1b7`。附件为DMG、ZIP、appcast.xml及SHA256SUMS，非draft、非prerelease。
- GitHub返回的四个asset SHA-256和长度均与本地最终包一致；随后从无鉴权公开URL重新下载到 `/tmp/syllapace-release-public-download`，运行 `tools/verify_release.py verify` 再次通过。
- 正式 `releases/latest/download/appcast.xml` 可访问并返回相同feed；已安装 `/Users/muse/Applications/Syllapace.app` 的检查更新窗口以中文显示“您使用的就是最新版！Syllapace 0.1.0是当前的最新版本”。通用设置的版本为0.1.0 (1)，中文偏好在重启后保留。
- 更新替换的隔离副本使用独立bundle ID、临时归档和仅127.0.0.1的HTTP测试源；测试服务器已关闭。最终发布包不包含测试ID、LSEnvironment或HTTP例外。

## Canvas token 自动续期与空状态修复验收

日期：2026-11-04。范围为 REQ-012 / AC-012，以及 AC-001 / AC-009 的空状态布局回归。当时源码构建已安装到 `/Users/muse/Applications/Syllapace.app` 并实际启动；应用仍标记为 0.1.0 (1)，公开 v0.1.0 下载包未替换。后续按用户要求作为 [0.1.1](releases/0.1.1.md) 发布，发布验证另行记录。

空状态偏左的已证实根因：`ContentUnavailableView` 位于 leading 对齐的父容器中，原先仅占内容固有宽度。现让它占满标题下方的剩余区域；新增 `empty-state` 探针，测量其横向边界和上下边界，覆盖旧布局检查遗漏的组件。

| 需求 / 验收 / 用例 | 层级、优先级及执行 | 实际结果与证据 |
| --- | --- | --- |
| REQ-012 / AC-012 / TC-012 | P1，Kit 模块与模拟契约；固定日期、合成 token 和模拟 HTTP 响应 | 新增 15 项测试通过。验证临近到期只向当前 token ID 发送一次有限期 PUT，正文仅含到期时间；远期、无到期日和已过期时不发送 PUT。`Tests/SyllapaceKitTests/TokenRenewalTests.swift` |
| AC-012 / TC-012 边界 | P1，短有效期重载、服务器缩短周期、最大周期、匹配歧义、错误响应、401/403/404/405/429/500、离线恢复、取消与跨源分页 | 模拟验证通过；请求不会轮换凭据、增加 scopes 或改写课程数据。短周期保留，服务器返回的更短周期用于后续调度；取消后不发起新 PUT。已在服务器处理中的请求无法保证撤回。 |
| AC-012 / 真实 UI | P1，在安装版打开 Canvas 设置，关闭并重新开启续期 | 默认开启；关闭后显示“token 自动续期已关闭”，恢复后显示“保存 Canvas token 后即可自动检查续期”。之前填写的 Canvas 地址已保存，当前没有保存 token，未发起真实账户续期。 |
| AC-001 / AC-009 / TC-013 | P1，Today、Timeline、Review、搜索无结果；中英文、浅深色、940×620 与 1280×800 | 32 张空状态及 4 张 Canvas 设置真实活动窗口截图均已阅图，无偏左、溢出或控件截断。`.impeccable/review/token-renewal-verified/`；可运行 `APP_SNAPSHOT_EMPTY=1 ./tools/snap.sh` 重新生成。 |
| TC-013 布局回归 | P1，`./tools/grid-lint.sh`、`swift tools/check-layout.swift <layout JSON files>` | 静态网格检查通过；36 份布局记录通过，其中 32 份包含空状态探针，4 份系统 Form 无自定义探针。`/tmp/syllapace-token-grid.log`、`/tmp/syllapace-token-layout.log` |
| 受影响模块与应用回归 | P1，`./tools/test.sh`、`./tools/selftest.sh`、`./build.sh` | 全套 69 测试 / 9 套件、9 项应用自测、Release 构建通过；测试与构建日志中零 Swift warning。`/tmp/syllapace-token-{tests,selftest,build}.log` |
| 本机交付 | P1，暂存安装、签名验证、重启、实际设置与主窗口检查 | `codesign --verify --deep --strict` 通过。用户资料和 Keychain 未被迁移或覆盖。已核对真实安装版空状态居中。旧应用包临时备份在 `/tmp/syllapace-app-backup-qfqfckqw/`。 |

验证中发现并处理的问题：首次测试编译因嵌套 `#require` 宏报错，拆分取值后通过；早期截图因应用未激活或隔离副本缺少窗口捕获许可而产生非活动图或 fallback，不计入验收。最终脚本使用独立临时预览应用、显式活动窗口检查，由已有捕获能力的运行器只截取该预览窗口，36 张最终图均为真实活动窗口捕获。预览应用与临时数据已自动清理，旧失败截图目录不作为交付证据。

本轮没有保存的真实 Canvas token，因此学校端元数据权限和真实到期延长 **未运行**；不能将模拟契约测试解释为该学校已经允许自动续期。应用退出期间不运行任务，长时间关闭导致过期时仍需手动替换。未做跨日运行、睡眠恢复的长时实测；最低 macOS 26 机器也未另行验证。

本轮证据评分：需求与验收覆盖 **23/25**（学校权限尚未联调），功能正确性与边界 **23/25**（真实服务器更新时间语义待验），测试充分性 **17/20**（无真实续期与跨日调度实测），架构与接口 **10/10**（纯策略、请求、应用调度分离，复用原连接器），维护与安全 **9/10**（凭据不变、同源与取消检查通过，未做独立安全审查），文档与交付 **10/10**（双语说明、可复现脚本、本机安装与限制齐备），合计 **92/100**。该评分仅针对本轮范围；实现与本机回归通过，真实账户续期仍待配置后验证。

## 0.1.1 包与源码同步交付

本轮对应 REQ-013 / AC-013 / TC-014。按用户要求，后续应用修订交付包含新版本公开安装包与更新 feed；本机安装保留给用户亲自测试自动检查和应用内升级。此要求已写入根目录 `AGENTS.md`，具体流程见 `RELEASING.md`。

- 版本从 0.1.0 (1) 递增到 0.1.1 (2)，包含 token 自动续期和空状态修复；Sparkle 公钥与固定 feed 地址保持一致。改动仅为版本及发布文档，没有再改动已验收的界面和业务代码。
- `./tools/test.sh`：69 项 / 9 套件通过；`./build.sh --release`：通过、零 Swift warning；`./tools/selftest.sh`：9 项通过。日志为 `/tmp/syllapace-0.1.1-{tests,build,selftest}.log`。
- `./tools/package_release.sh`：DMG、ZIP、appcast.xml、SHA256SUMS 已生成到 `build/releases/0.1.1/`；包内公钥验证 Ed25519、ZIP 解包签名、版本/架构/feed 约束、DMG 完整性均通过。日志为 `/tmp/syllapace-0.1.1-package.log`。
- 发布前已只读记录本机 Info.plist、可执行文件和 CodeResources 的 SHA-256；构建与打包后相同。本机仍为 0.1.0 (1)，没有替换、重新启动或发起更新检查，也没有修改更新偏好和计时。其更新器默认约 24 小时自动检查，下载安装由用户确认。
- 已公开 [v0.1.1](https://github.com/yangbo-s/Syllapace/releases/tag/v0.1.1)，源码 tag 对应 `9e314b92a3f465e3c0350325d823bb8a201caadb`，是正常 Release 且为 latest。GitHub 上四个 asset 的大小与 SHA-256 均与本地包一致；从无鉴权公开地址重新下载也全部匹配。正式 latest feed 的内容与该 release 的 appcast 相同，版本为 0.1.1、build 为 2。
- 公开下载包再次通过 `tools/verify_release.py verify`：SHA-256、Ed25519、ZIP 解包签名、DMG 完整性通过。另只读挂载 DMG，确认其中的版本、Info.plist、可执行文件与 ZIP 一致，嵌套签名有效，验证后已卸载。新包公钥与本机旧版一致。证据：`/tmp/syllapace-0.1.1-public-s5t82tst/`、`/tmp/syllapace-0.1.1-public-verify.log`。
- 发布及回读后，本机三个文件的指纹仍与发布前相同，版本仍为 0.1.0 (1)。自然自动检查、提示、安装和重启由用户在真实本机验证，本轮没有执行，也不记录为已通过。
- 已解决的验证问题：按 tag 查询草稿返回 404，改由 release 列表定位 ID 后完成上传资产校验；首次回读误用了草稿 `untagged-*` 临时地址，公开后刷新正式元数据并使用版本地址，四个公开文件验证全部通过。这两条注意事项已补入发布流程。

本次发布范围证据评分：需求覆盖 **25/25**（公开包、feed、源码与保留本机旧版均核验），功能边界 **24/25**（更新器代码未变，本轮未再执行真实跨版本替换），测试 **17/20**（包与更新源通过，最低系统和自然调度仍未实测），架构接口 **10/10**（复用既有发布和签名链），维护安全 **9/10**（签名和附件一致，仍未 Apple 公证），文档交付 **10/10**（双语说明、公开回读、版本边界和长期交付约定齐备），合计 **95/100**。该分数针对本次发布过程，不替代 Canvas 真实续期和本机升级验证。


## 0.2.0 学期与来源修复交付

范围：REQ-014—017 与 REQ-013；版本 0.2.0，build 3。采用原有原生 SwiftUI、Canvas PAT、BYOK、EventKit 与 Sparkle 技术栈，没有新增依赖。中英文 README 与 [发布说明](releases/0.2.0.md) 已同步更新。

| 需求 / 验收 / 用例 | 层级、前置与执行 | 实际结果及边界 |
| --- | --- | --- |
| REQ-014 / AC-014 / TC-015 | P1，模块/应用自测；schema-1 合成归档、Fall/Spring/Default Term 课程和本地事项 | 读取时不改原文件，首次成功保存保留上一版本备份；未确认范围隐藏历史 Canvas 数据且不自动获取正文；明确的 All semesters 与未选择区分；选课状态重载一致，切换保留历史。`SemesterSemanticsTests.swift`、`SelfTest.swift`；所有页面、桌面卡片、导出与新增 Calendar 写入共用 scopedEvents/scopedSources。 |
| REQ-015 / AC-015 / TC-016 | P1，模拟 HTTP 契约与真实 Canvas GET；按所选课程读取原生来源，模拟权限失败、分页、重复引用与链接上限 | Announcements、Modules、Page、syllabus、附件元数据和链接接入通过；Files 目录失败不会中断其余来源；受限来源给出 warning。公共导入模拟证明不带 Authorization/cookie，拒绝登录页及不安全重定向，Google Sheets 保留 gid。`CanvasCoverageTests.swift`、`SemesterSemanticsTests.swift`；真实学校仅对当前可访问资源验证。 |
| REQ-016 / AC-016 / TC-017 | P1，模块测试；同名不同 ID、Quiz 对应 Assignment、明确上课起止/地点、改期与未知成绩 | 原生 ID 防重复且保留不同作业；session/project/quiz 分类，结束时间变化进入冲突；ICS 保留结束和地点，Calendar payload 保留明确结束及地点备注；缺失成绩保持未知。`CanvasCoverageTests.swift`、`SemesterSemanticsTests.swift`、`ConnectionCompatibilityTests.swift`。 |
| REQ-017 / AC-017 / TC-018 | P1，模拟 token/模型契约与真实只读/合成联调 | 可变长度掩码、分片前缀、歧义和矛盾身份通过；真实 token 元数据仅匹配一条。现代模型请求参数及明确 400 后一次兼容重试通过；真实配置模型从虚构 Quiz 文本提取日期成功，没有发送真实课程文档。凭据异步读取，配置变更后不将旧凭据发往新地址。 |
| REQ-013 / AC-013 / TC-019 | P1，Release 构建、应用自测、窗口/网格检查、打包签名与公开下载 | DMG/ZIP、签名 appcast 和 SHA256SUMS 的本地及公开回读验证通过；latest 为 build 3。本机安装 0.1.1 (2) 指纹未变，保留给用户测试更新。 |

### 自动化与真实联调证据

- `./tools/test.sh`：100 项 / 12 套件通过，日志 `/tmp/syllapace-tests-020.log`。
- `./build.sh --release`：成功，生成仓库 `build/Syllapace.app`；日志 `/tmp/syllapace-build-020.log`。
- `./tools/selftest.sh`：16 项通过，包括旧资料等待确认、学期作用于事件/来源/审核、切换保留和重载；日志 `/tmp/syllapace-selftest-020.log`。
- 临时只读诊断读取用户授权的 Keychain 凭据，在内存中完成 Canvas 课程发现、选定学期内容同步和 token 唯一识别；未发 PUT、未下载附件、未改写真实归档。模型只接收虚构日期文本，返回一个有日期的 Quiz 候选。临时程序及源文件已删除，真实课程/学校/账户数据和凭据未写入仓库。
- 中英文各 33 张，共 66 张真实活动窗口截图：`build/verification/0.2.0/final/{en,zh-Hans}/`；覆盖主页面、完整/窄窗选课、结束时间编辑、导入、来源链接、桌面卡片、四页 Settings 及空态。前一完整批逐页阅图后，最终批复核本轮修正的网格、日期格式与选中色。英文和中文的课表选择、Session 日期/时间、来源链接、窄窗审核均无截断或重叠；General 的语言值和界面一致。Canvas 设置实际可滚动，续期开关在首屏下方，不以首屏截图声称已覆盖该控件。
- `./tools/grid-lint.sh` 与最终 66 份运行时布局记录全部通过；日志 `/tmp/syllapace-layout-020-final.log`。截图日志 `/tmp/syllapace-shots-020-final.log`；之前未激活/中断目录不作为最终证据。最初网格检查发现 Picker 到列表 41pt，修正装饰分隔线后为 40pt，未放宽断言。
- `./tools/package_release.sh`：四项资产生成到 `build/releases/0.2.0/`；SHA-256、appcast 版本/架构约束、包内公钥验证 Ed25519、ZIP 解包 app 签名、DMG 完整性通过；日志 `/tmp/syllapace-package-020.log`。公开发布和回读通过，见下方记录。
- 打包前只读核验本机安装仍为 0.1.1 (2)，Info.plist 与可执行文件 SHA-256 和发布前记录一致。没有替换应用或修改更新检查计时、偏好。

### 验证中发现并修复的问题

- 课程 term 的访问窗口开始年不一定是教学年，改为使用 term 名称中唯一明确的四位年份；测试覆盖跨年访问窗口。
- HTML 内嵌 schedule 在达到链接上限时补充明确的截断提示；新增 200 个链接后嵌入 iframe 的组合测试。Calendar 冲突列表和恢复入口一并遵守当前课程范围，范围外调用自测保证不进入 EventKit。
- 原生不同 ID 的同名作业会被相似标题冲突逻辑合并，改为保留独立原生事项；Quiz 与 Assignment 的相同原生身份仍去重。
- 旧档升级后重新管理课程先发现当前账户元数据；空/未知学期不静默变成全部课程，All semesters 是显式选择。
- 中文结束时间 DatePicker 补充 locale 与语言变化时的独立 control ID，使起止使用相同格式；侧栏选中图标继承系统前景色，避免蓝色选中态上青绿对比偏低；两条装饰分隔线不参与垂直高度，选课选择器到列表间距由 41pt 校正为 40pt。
- 直接运行构建包时，部分截图窗口未取得焦点；失败记录不作为视觉证据。最终改用已有预览脚本的临时独立 bundle ID、临时归档及真实窗口捕获；语言 Picker 通过仅本进程参数与 APP_LANGUAGE 一致，不写用户偏好。
- 初次辅助诊断调用可能 PUT 的维护入口，自动审批拒绝执行；删除该入口后仅以 GET 查询及纯匹配函数验证，获得授权并通过。另一辅助程序起初缺 SwiftPM 资源路径，在进入模型测试前失败；配置正确包资源路径后通过，正式应用的资源由自测验证。

### 明确未验与范围边界

PAT 的真实延期没有执行；当前确认的是元数据可读和唯一匹配，学校是否接受续期 PUT 尚不能据此保证。退出应用期间无后台任务，过期 token 仍需手动替换。长时间睡眠恢复和跨日调度未实测。更新的公开源/签名验收不等于本机已完成下载安装。

EventKit 权限及真实写入、本机 0.1.1 → 0.2.0 更新、最低 macOS 26 机器、完整 VoiceOver 和长期性能未在本轮验证。私有 Google 授权、独立 Piazza/Gradescope 内容抓取、New Quizzes 题目不在本轮范围；外链按用户触发读取公开内容，其他保留浏览器入口。归档升级为 schema 2 后旧版本不能读取，备份保存上一次有效文件。应用仍是 ad hoc 签名，未 Apple 公证。

设计验证使用现有 DESIGN.md 与原生 SwiftUI 规则。Impeccable sidecar 的旧设计元数据和平台 schema 警告不影响运行，未在本轮扩展为设计系统迁移。


### 0.2.0 公开发布后核验

- 已公开 [v0.2.0](https://github.com/yangbo-s/Syllapace/releases/tag/v0.2.0)，源码 tag 对应 `87a8f97`；正常 Release、非 prerelease，已设为 latest。源码已推送 `main`，Release 内含 DMG、ZIP、appcast.xml 与 SHA256SUMS。
- 草稿阶段核对 GitHub 四个资产的名称、上传状态、大小及 SHA-256，与本地包全部一致后才公开。公开后刷新正式元数据，从无鉴权下载地址回读到 `/tmp/syllapace-020-public-cgok68xn/`，四项文件与本地相同；正式 latest feed 返回相同 appcast，版本 0.2.0 / build 3。
- 对公开 ZIP 再运行 `tools/verify_release.py verify`：SHA-256、包内公钥验证 Ed25519、应用嵌套签名及 DMG 完整性通过。日志 `/tmp/syllapace-public-020-verify.log`。另只读挂载公开 DMG，确认其版本、Info.plist、二进制与经过验证的构建一致，`codesign --verify --deep --strict` 通过，验证后卸载。
- 发布后再次只读比对已安装 0.1.1 (2) 的 Info.plist、可执行文件 SHA-256，均与发布前相同；新旧 Sparkle 公钥一致。本轮未替换、启动或退出用户安装，未触发其更新检查、下载安装，也未修改更新计时或偏好。自然检查和 0.1.1 → 0.2.0 安装由用户亲自验证，不能记录为本轮已通过。
- 最终视觉独立复核：前一完整批中英 66 图逐页审阅；最终批中英各 33 图齐全，复核受影响的 16 图（课程 sheet 宽/窄浅深、Session 编辑器与侧栏）。起止日期本地化一致，无剩余视觉阻断。最终截图中侧栏是灰底原生选中色，不声称实际复现了白图标/蓝底组合。临时预览应用、演示资料和诊断程序均已清理。

### 本轮证据评分

评分仅针对 0.2.0 约定范围，不替代全部产品或所有学校实例的验收。

| 维度 | 得分 | 证据与扣分边界 |
| --- | --- | --- |
| 需求与验收覆盖 | 24/25 | REQ-014—017、REQ-013 有测试及发布证据；真实 PAT 延期未执行，学校更新权限仍需后续确认 |
| 功能正确性与边界 | 23/25 | 迁移、学期范围、原生身份、权限部分失败、日期语义、链接上限及凭据隔离回归通过；跨学校可选 API 差异与长期 token 调度未全面实测 |
| 测试充分性与结果 | 18/20 | 100 项 / 12 套件、16 项应用自测、真实 Canvas GET 与合成模型调用、66 图/布局记录及公开资产验证通过；未测最低 macOS 26、本机自然更新及真实 EventKit 权限写入 |
| 架构、接口与扩展性 | 10/10 | 发现和正文同步分离，scope 集中在 AppModel，原生来源/事项分别建模，schema 1 向后读取且保存前备份 |
| 代码质量、安全性与维护 | 9/10 | Swift 6 构建无编译警告，独立代码复核发现的边界均修复；未做独立安全审计，发行仍未 Apple 公证 |
| 文档与交付完整性 | 10/10 | 中英 README/发布说明、需求追踪、公开安装包与签名 feed、实际回读及本机保留核验齐备 |
| **合计** | **94/100** | **0.2.0 修复与发布范围通过；上述真实环境未验项明确保留。** |

## 0.3.0 — 统一资料与校历体验

本轮范围为 REQ-018—023、REQ-013。用户明确将原生 WidgetKit 发行延后；本版交付 AppKit 桌面卡片，不要求 Apple Developer 账号。WidgetExtension 与共享快照仅保留可编译预备源码，未注册、未嵌入安装包，不计为已发行功能。

| 需求 / 验收 / 用例 | 实现与已验证行为 | 证据 |
| --- | --- | --- |
| REQ-018 / AC-018 / TC-020 | 文件、文字、公开链接进入同一输入/预览；候选保留原文，可编辑、批量选择、保存无日期资料及撤销。并发变更阻止旧预览覆盖；撤销保留后续编辑，Calendar 删除使用 rejected 标记，手动决定清除撤销标记。 | MaterialImportDraft、ImportUndo、WorkspaceCustomizationTests、App SelfTest |
| REQ-019 / AC-019 / TC-021 | OpenAI/Anthropic/DeepSeek/custom 模型发现、选择、取消、过期结果保护；Anthropic 原生 Messages JSON schema；旧endpoint凭据兼容。 | ModelProviderTests 及模型设置中英浅深色窗口；真实账号模型调用本轮未执行 |
| REQ-020 / AC-020 / TC-022 | 课号、名称、组合、自定义，全局默认与每课覆盖；偏好独立于 Canvas 返回元数据，搜索兼顾原始名称与自定义名。 | WorkspaceCustomizationTests、SelfTest、course-display 与 Review 窗口 |
| REQ-021 / AC-021 / TC-023 | 独立学校校历、学期/日期窗口、ICS 重复/例外/取消、多日全天；学校假期不推导课次取消。CMU 官方滚动订阅与年度PDF入口；XLSX保留日期、工作表和单元格上下文。 | AcademicCalendarTests、SpreadsheetReaderTests、真实 CMU 公开资料验证记录 |
| REQ-022 / AC-022 / TC-024 | Instructure 匿名学校搜索、缓存、手工地址回退；不读取或发送 Canvas token。 | SchoolDirectoryTests、官方目录真实匿名GET、school-search 窗口 |
| REQ-023 / AC-023 / TC-025 | 桌面紧凑/展开、下节课/最近截止、7日列表、置顶/锁定/边缘吸附、偏好；demo不写真实偏好。 | Swift6独立typecheck、SelfTest、desktop两模式中英浅深色窗口 |
| REQ-013 / AC-013 / TC-026 | 0.3.0 (4)，保持既有更新公钥、GitHub feed；不覆盖用户安装。 | 发布后公开回读与安装指纹记录在本节后续核验中补充 |

### 工程与视觉证据

- `./tools/test.sh`：169 项、19 套件通过，完整日志 `build/verification/0.3.0/tests.log`；Swift 6 编译无警告。包含 2 万条同名 ICS 事件的身份与合并测试，索引实现避免逐条全表扫描。
- `./build.sh --release`、`./tools/selftest.sh`、网格 lint 与实际窗口布局检查使用仓库 `build/` 和临时资料库。最终输出日志放在 `build/verification/0.3.0/`，不会读取用户课程或模型凭据。
- 首轮中英各47张实际窗口；独立审查覆盖全部中文与英文新增页面。发现并修复：桌面两行标题占位导致的日期不齐、资料/显示设置抢焦点、导入页无效空白、示例日期与证据不符、长课程名偶发绘制缺失、深色分段与勾选控件对比不足。最终复核图与定向控件图分别保存在 `final/` 和 `controls/`。
- 公开资料验证见 [校历验证记录](research/academic-calendar-0.3.0-verification.md)：CMU ICS 107 条事件、0 警告，实际范围 2026-11-09—2027-08-10；年度教学日 XLSX 1 表/105 行。没有将滚动 feed 当作完整全年数据。
- 独立代码审查修复了：XLSX sharedStrings 在单行大量展开时的内存上限、ICS 明确取消/EXDATE 未转审核、持续时间溢出、重复事项展开后的总载荷上限、任务取消，以及不同 ICS UID 被标题误合并。异常来源不会按“缺席”删除历史。
- schema 1/2 在成功保存时迁移到3；额外保留一次性 `archive.json.schema-<旧版本>.backup`，不会被后续滚动备份覆盖。旧 app 不可直接读取 schema3。

### 未验项和边界

原生 WidgetKit/App Group 系统分发按用户要求延期。Anthropic、DeepSeek 与模型目录的新真实密钥调用仅有 mock 契约测试；没有为验证发送用户课程或产生真实模型费用。真实 EventKit 权限/写入、最低 macOS26 机器、完整 VoiceOver、多显示器长时间运行与本机 0.2.0→0.3.0 自然更新未在本轮执行。卡片只随应用运行；登录后私有网页需导出或粘贴，扫描PDF需外部OCR。模型单文档限制64,000字符、最多300候选；不猜测正文里的无限重复课表。应用仍为ad hoc签名，未Apple公证。

Impeccable 的旧sidecar与平台schema提示沿用既有设计文档处理，没有借本任务迁移设计系统。公开发布回读记录将在完成上传后追加。


### 0.3.0 发布前验收与证据评分

最终正式包通过169项/19套件测试与25项隔离应用自测。编译、网格lint、英文47份和中文47份窗口布局文件均通过；最终截图94张完成，独立复核见本节视觉记录。额外课程选择控件截图作为最后一次局部复核。最新 `build/releases/0.3.0-final/` 四个资产通过本地哈希、Ed25519、ZIP嵌套签名、DMG完整性检查；ZIP二进制与最终构建逐字节一致，未嵌入Widget扩展。发布前已安装0.2.0(3)的Info.plist与二进制SHA-256和开工基线一致。

| 维度 | 得分 | 证据与扣分 |
| --- | --- | --- |
| 需求与验收覆盖 | 24/25 | REQ018—023都有实现/契约/交互证据，Widget按用户决定延期；多账号真实模型连接未测 |
| 功能正确性与边界 | 23/25 | 归档迁移、撤销/冲突、ICS时区/重复/例外、XLSX载荷、学期范围通过；学校API差异与长期调度未穷举 |
| 测试充分性与结果 | 18/20 | 169测试、25自测、真实公开CMU资料、94实际窗口与布局；真实EventKit和本机跨版本更新留给用户 |
| 架构、接口与扩展性 | 9/10 | provider与transport分层，日历独立ownership，归档可恢复；AppModel继续承担多个工作流，后续可按实际规模拆分 |
| 代码质量、安全与维护 | 9/10 | 无编译警告、无凭据公开请求、独立审查修复资源上限/取消/撤销边界；未做独立安全审计或Apple公证 |
| 文档与交付完整性 | 9/10 | 双语README、版本说明、需求追踪、签名安装包齐全；公开上传与回读待本节后续核验 |
| **合计** | **92/100** | **发布前门禁通过；公开交付尚须完成上传与回读。** |
