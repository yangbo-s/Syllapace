# 实施与验收记录

日期：2026-11-04。范围见 [ENGINEERING.md](ENGINEERING.md)。本记录区分实现、自动化证据和真实外部联调，不能用单元测试替代账户与系统权限验收。

## 当前结果

原生 macOS 应用、核心数据处理、Canvas/BYOK 适配、桌面卡片与 EventKit 适配已实现。完整项目的 **49 项 Swift Testing 测试、7 个测试套件通过**；应用自测的 **7 项检查通过**。Debug 与 Release 构建成功，所查构建日志没有 Swift 编译警告。

真实 Canvas 账户、BYOK 服务和用户授权后的 EventKit 读写尚未运行。浅深色窗口截图、窄窗口及空状态已完成阅图；修正后的网格检查通过。真实 UI 点击与快捷键流程已检查。**当前不是全部 P0/P1 验收通过的正式发布结论。**

环境：arm64 macOS 27.0.1，Xcode 提供 Swift 6.4.2，项目目标 macOS 26+、Swift 6 模式。macOS 26 最低版本运行兼容性尚未单独实测。

## 执行证据

| 检查 | 实际结果 | 证据 |
| --- | --- | --- |
| `./tools/test.sh` | 49/49 通过，7 套件 | 本轮日志 `/tmp/syllapace-tests-final.log`；测试源码见下表 |
| `./tools/selftest.sh` | 7/7 通过，`SELFTEST complete` | `/tmp/syllapace-selftest.log`；`Sources/Syllapace/SelfTest.swift` |
| Debug 构建 | 通过，生成 `.app` | `/tmp/syllapace-build-final.log` |
| Release 构建 | 通过，生成并签名 `.app` | `/tmp/syllapace-release.log` |
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

## 100 分证据评分

以下为当前实现及已有验证证据评分；真实外部联调缺失单列为验收边界。独立视觉审阅为 94/100，仅代表本轮截图与交互范围，不替代功能验收。

| 维度 | 得分 | 证据、扣分及后续验证 |
| --- | --- | --- |
| 需求与验收覆盖 | 22/25 | 八项需求均有实现入口；界面与核心交互验证完成，账户接入和系统日历权限尚未闭环 |
| 功能正确性与边界处理 | 21/25 | 日期/重复/冲突/存储/连接器/日历规划器测试通过；实际端到端外部行为未验证 |
| 测试充分性与结果 | 17/20 | 完整项目 49 项测试 + 7 项应用自测及真实 UI 冒烟检查通过；缺少真实外部联调、Calendar 客户端导入及代表性大纲评估 |
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
- 最终抽象几何图标已检查 default/dark/tinted/clear 及 16/32pt 小尺寸，修正了深色底色；已在实际安装应用的 About 窗口核验新图标。纯 SVG 母版、三色变体和使用说明见 `Brand/`，原生分层源见 `Icon/AppIcon.icon/`。未进行完整 VoiceOver、窗口拖拽、多显示器/Spaces、长时间性能与真实权限交互验收。

## 仍待真实环境验证

用户自行配置后的 Canvas、BYOK、EventKit 实测；机构权限、模型兼容性、系统授权与外部日历修改/恢复需逐项核验。凭据只在应用中输入，不写入仓库、日志、截图或测试夹具。
