# 实施契约与验收
GOAL-001：为学生提供可追溯的本地学业日程。

| 需求 / 验收 | 模块 | 可观察验收 |
|---|---|---|
| REQ-001 / AC-001 | 原生应用 | Swift 6 构建，空状态与示例模式，浅深色界面 |
| REQ-002 / AC-002 | Canvas | HTTPS、凭据Keychain、分页、课程/作业/大纲/文件读取，部分失败保留数据 |
| REQ-003 / AC-003 | 文档 | PDF/DOCX/TXT/MD导入、证据与日期精度保留 |
| REQ-004 / AC-004 | 提取审核 | BYOK结构化候选、编辑/批准/拒绝、重复导入无重复、改期保留用户决定 |
| REQ-005 / AC-005 | 日程 | 时间线、详情、完成状态、搜索与课程过滤、离线保存 |
| REQ-006 / AC-006 | 桌面卡片 | 独立紧凑窗口、置顶选项、进入主界面 |
| REQ-007 / AC-007 | EventKit | 用户主动授权、专用日历、映射、外部编辑冲突、失败恢复 |
| REQ-008 / AC-008 | ICS | 稳定UID、全天日期、转义与换行折叠 |
| REQ-009 / AC-009 | 语言 | 设置中选择跟随系统、English、简体中文，界面即时切换且重启保留；Canvas 等术语和用户资料原文不变 |
| REQ-010 / AC-010 | 更新 | 应用菜单/通用设置检查 GitHub 上的 Sparkle feed，处理无更新、失败、有更新；Ed25519 验证后用户确认下载安装 |
| REQ-011 / AC-011 | 首发 | GitHub v0.1.0 包含可解包启动的 arm64 ZIP、DMG、包含更新包签名的 appcast、SHA256SUMS 和明确的系统/签名/验证边界 |
| REQ-012 / AC-012 | Canvas token 续期 | 识别当前个人 token，在有效期末段自动延长到期时间；只修改唯一匹配的当前 token，关闭后不再发起续期，失败不影响课程资料 |
| REQ-013 / AC-013 | 持续发布 | 应用功能或修复交付时同步发布递增版本的 DMG、ZIP、签名 feed 与校验值；公开回读验证，并保留用户本机旧版供其测试更新 |

IN-001：Canvas HTTPS host + PAT；模型HTTPS endpoint + key + model；用户选择文档（UTF-8文本、PDF、DOCX）。密钥仅Keychain。
OUT-001：版本化本地归档、候选/确认事件、系统日历、ICS文件。网络/解析错误向用户显示，不清空已有数据。
CON-001：macOS26+，Swift6，SwiftUI+AppKit，用户自行运行，无后端。真实Canvas/BYOK/EventKit联调需用户配置，仅以合成数据自动测试。
ASM-001：默认系统时区，导入时明确学年；无法解析日期保留待审核。应用支持英文和简体中文，默认跟随系统；工程交流中文。
OOS-001：Windows、OCR、其它LMS、自动提交作业。
ADR-002：原生Swift项目；对比直接fork Tauri，选择系统集成和原生交互，承担重写UI成本。持久化先使用版本化原子JSON，文档体量较小时无数据库依赖。
MOD-001：SyllapaceKit纯数据/规则/存储/连接器；MOD-002：SwiftUI状态与视图；MOD-003：EventKit与桌面窗口。
IF-001：课程、来源和事件ID稳定；来源hash仅版本指纹。API失败抛出明确错误，批量同步按课程保留成功结果。日期缺失为nil，不自动确认。

阶段：契约 → 各模块 → 集成 → 单元测试 → 真实窗口浅深色批量检查 → 一轮修正 → 验收。
测试记录与100分证据评分在 docs/ACCEPTANCE.md 交付；未运行的外部实测独立披露。

## 功能与接口明细

| 编号 / 优先级 | 行为与边界 |
|---|---|
| FUNC-001 / P1 | 用户显式导入文件，解析为来源与待审事件；空文本、损坏/超限文件显示错误，不删除既有资料。 |
| FUNC-002 / P1 | 规则与模型结果都进入 Review；批准后进入日程。无日期候选需先补日期；手动修改和源日期观测分开保存。 |
| FUNC-003 / P1 | 重复同步按稳定 ID 合并；来源改期保留当前决定并展示 proposedDate。暂时缺项和获取失败不表示删除。 |
| FUNC-004 / P1 | Canvas 分页读取、保留部分成功；后台刷新仅在用户启用且应用运行期间发生。附件由用户选择下载。 |
| FUNC-005 / P1 | EventKit 连接由用户发起；只写专用本地日历。重复同步复用映射；外部编辑/删除要求显式处理。 |
| FUNC-006 / P1 | 搜索、课程筛选、完成切换和桌面事件跳转使用同一资料库；桌面卡片可置顶。 |
| FUNC-007 / P1 | ICS 导出仅含已确认事件；全天事件保持日期精度，DTEND 使用下一日，UID 稳定。 |
| FUNC-008 / P0 | 密钥仅保存到 Keychain、按目标地址隔离；资料损坏不得覆盖有效备份；模型和文档内容均视作数据。 |

### IF-002 输入与数据语义

- Canvas 地址：必填 `String`，HTTPS origin，无 user/password/query/fragment；token 为非空可打印 ASCII，仅进入 Authorization。合法形状 `https://canvas.example.edu`；`http://canvas.example.edu?token=x` 非法。
- 模型：HTTPS base URL、非空 model（≤200 字符）、非空 key；默认 endpoint 为 `https://api.openai.com/v1`，model 无默认值。支持兼容 chat completions 的服务，HTTP 本地服务不在当前接口内。
- 文档：UTF-8 TXT/MD/HTML、文本 PDF 或 DOCX；文件≤20MB、PDF≤150页、提取文本≤2MB。扫描 PDF 无可提取文本时需先 OCR。
- 学年：UI `Int`，默认当前年、2020…2100；提取器底层接受1900…2200。时区使用有效 IANA `String`，本地导入默认设备时区。未给出日期为 `nil`，不填虚构时间。
- 事件：`AcademicEvent.id` 与 `courseID` 为非空身份字符串，`date: Date?`，`dateOnly: Bool` 默认 true，`state` 为 pending/approved/rejected/conflict；`completed` 默认 false。来源保留 evidence、sourceID/URL、内容 hash 和 fetchedAt。精确瞬间与全天浮动日期分别处理。
- 最小文件示例见 `fixtures/syllabus.md`；含歧义日期和多日期句子的无效推断用例见 `CoreTests.swift`，模型多余字段/无证据结果见 `ConnectorTests.swift`。

### IF-003 网络、错误与状态

| 接口 | 调用及输出 | 错误/恢复与幂等 |
|---|---|---|
| `CanvasClient.sync()` | UI → Kit → Canvas REST v1；读取课程、作业、日历事件、大纲与文件。返回 courses/events/sources/files/warnings。 | HTTPS、同源分页、有限响应和分页数；每课程/资源错误进入 warnings，成功结果保留。GET 可重试；无自动无限重试或远程写入。 |
| `CanvasClient.download(file:)` | 用户选择文件后下载到临时 URL，再交 DocumentReader。 | 下载重定向不转发 Bearer，拒绝非法目的地和超限内容；调用方最终清理临时文件。 |
| `LLMClient.extract(source:year:timeZone:)` | POST `<base>/chat/completions`，JSON messages + model/temperature/max_tokens/response_format。输出 pending 事件数组，≤300项。 | 输入≤64000字符，JSON输出/日期/时区/证据校验；不完整输出或无依据片段整体拒绝，不把模型结果直接确认为事件。请求由用户触发，失败不自动重复计费请求。 |
| `ArchiveStore.load/save` | UI → 原子 JSON 文件，schemaVersion=1；成功保存保留上次有效备份。 | 不存在返回空资料库；损坏/未知 schema 抛错，拒绝覆写；新版本迁移尚未实现。 |
| `CalendarBridge.connect/sync` | UI → EventKit；保存 calendarID、稳定事件映射及未完成操作意图。 | 同步/连接互斥；未授权、本地来源缺失、映射损坏显示可处理错误。写入后映射失败通过意图和归属标识恢复。外部修改阻止覆盖。 |

具体错误类型为 `ConnectorError`、`DocumentError`、`ArchiveError`和 `CalendarBridgeError`（以源码枚举/类型为准）；UI 显示本地可诊断消息，不显示 Authorization 内容。网络错误、取消和部分成功区别处理。模型/网络工作的 async 边界不持有 SwiftUI View；应用状态归主 actor，系统日历由独立适配层管理。

## 阶段门禁与交付

契约、模块实现、合成数据集成、构建与自动化检查已有证据。首个公开包由用户明确要求发布，作为早期版本披露真实 Canvas/BYOK/EventKit 尚未联调的边界，不以发布替代这些验收。当前环境没有 Developer ID 证书，应用 ad hoc 签名，尚未公证；发布页说明系统首次打开方式。源码、构建脚本、测试、示例、设计文档和验收记录一并交付。

## 0.1.0 语言、更新与发布契约

GOAL-002：使本地客户端可供中英文用户安装使用，并持续从项目 GitHub Release 获取可信更新。

- FUNC-009：界面标签、提示、错误、日期与菜单使用选定语言；Canvas、Syllapace、OpenAI、API、PDF、DOCX、ICS 等名称保持原文。课程名、证据、用户输入和归档键不翻译。应用内立即切换，系统菜单及 Sparkle 标准窗口重启后生效。
- FUNC-010：手动检查入口在应用菜单与 Settings → General；自动检查可由用户选择。下载与安装由 Sparkle 2.10.1 完成，更新包需通过内嵌公钥验证。demo/selftest/snapshot 禁止自动更新网络与安装行为。
- IN-002：`appLanguage` 非秘密偏好为 `system/en/zh-Hans`，未知值回退系统；不支持的系统语言回退英文。`APP_LANGUAGE` 仅供隔离验证覆盖。更新输入为 HTTPS GitHub Release 的 appcast.xml，版本使用递增 `CFBundleVersion`。
- OUT-002：应用选择持久化到本应用 UserDefaults；本地归档 schema 不变。首发输出 `Syllapace-0.1.0-macOS-arm64.zip/.dmg`、`appcast.xml`、`SHA256SUMS`；未更新/离线显示可重试的原生状态，不更改用户数据。
- CON-002：仅 macOS 26+ Apple Silicon；更新私钥保存在登录 Keychain `app.syllapace.mac` account，不入仓库、包或日志。GitHub 托管公开包与 feed，不接收课程或凭据。
- OOS-002：本次不新增 Intel/Windows、OCR/中文文档提取算法、后台代理、iCloud 目标或 Apple 公证。
- ADR-003：比较自写下载/替换器与 Sparkle，选择 Sparkle 的验证、安装与失败处理，新增一个锁定版本的成熟依赖；GitHub `releases/latest/download/appcast.xml` 提供 feed，ZIP 为更新源，DMG 为首次安装入口。
- MOD-004：Kit 的 L10n/资源供 SwiftUI、AppKit、后台错误共享；App 管理偏好与 locale，保持数据模型。MOD-005：UpdateController 包装 Sparkle 生命周期/状态，UI 仅触发与绑定。MOD-006：build/package 脚本生成签名可验证的包，公开发布由显式版本/tag执行。
- IF-004：GitHub URL `https://github.com/yangbo-s/Syllapace/releases/latest/download/appcast.xml` 使用 HTTPS 重定向；feed与包版本、签名、长度、系统与架构约束一致。离线/无feed/签名错误由 Sparkle 阻止安装并报告错误；不回退未签名安装。

| 测试 / 验收 | 证据要求 |
| --- | --- |
| TC-009 / AC-009 | 语言解析/回退、资源键与插值一致性、术语保留测试；中英浅深色实际窗口；实际设置切换和重启保存 |
| TC-010 / AC-010 | 更新入口可用性、自测不联网；本地签名包与feed验证；实际GitHub检查，更新完整流程在隔离应用副本验证 |
| TC-011 / AC-011 | release构建、签名结构、framework及资源自包含；ZIP/DMG完整性及SHA256；公开Release资产回读核对 |

门禁顺序：契约 → 语言/更新实现 → 测试与真实界面 → 隔离安装和更新验证 → 公开源码/tag/Release → 公网feed与下载核验。执行结果与100分证据评分记录于 `ACCEPTANCE.md`。

## Canvas token 续期与空状态修复

- FUNC-012：自动续期默认开启，可在 Canvas 设置关闭。启动、保存连接和同步时启动检查；依据到期时间调度，正常检查间隔最多六小时，暂时失败十五分钟后重试，权限或有效性失败二十四小时后重试。仅在剩余有效期不大于原周期的四分之一且不超过七天时续期。应用退出期间不执行任务；已过期 token 提示重新生成。
- IF-005：Kit 使用 HTTPS `GET /api/v1/users/self/user_generated_tokens` 分页读取元数据，通过 `token_hint` 或 `visible_token` 唯一匹配当前凭据；`PUT /api/v1/users/self/tokens/:id` 只发送 `token[expires_at]`。不发送 `regenerate`、不改变 scopes，不自动建立其它 token。续期周期保留首次确认值并最多三十天；接受服务器限制，拒绝时不尝试绕过。
- OUT-003：Keychain 中原 token 不变，避免轮换后凭据丢失；按源站及凭据摘要隔离保存非秘密到期元数据。UI 区分有效、已续期、无到期日、无法自动续期、已失效和暂时失败。切换地址/凭据或关闭开关时取消旧任务，旧响应不得覆盖当前连接状态；已经发送的远程请求可能仍由服务器完成。
- ADR-004：选择延长原 token 的有效期而不是生成替代 token；操作幂等且不导致服务器与 Keychain 的凭据值不一致。自动化仅使用模拟响应；学校实例的真实权限单独验证。
- MOD-012：`CanvasTokenLease` 负责纯到期策略；`CanvasClient.maintainAccessToken(previousLease:now:)` 负责同源元数据读取和有限期更新；应用层 `CanvasTokenRenewal` 负责 Keychain 读取、调度、非秘密缓存和本地化状态。课程同步与续期各自运行，续期失败不修改归档。
- IF-005 字段：正整数 `id`、ISO 8601 `created_at`、必需但允许 null 的 `expires_at`、`workflow_state`，以及至少一个可唯一匹配的 token 提示。合法更新正文为 `{"token":{"expires_at":"2026-12-01T00:00:00Z"}}`；缺少 `expires_at`、无效日期、重复提示或响应 ID 改变均不得确认为续期成功。HTTP 401 表示凭据失效，400/403/404/405/422 表示本次无法自动续期；暂时网络错误保留原凭据并稍后重试。沿用请求超时、响应大小和分页上限。
- IF-005 依据：[Canvas Access Tokens API](https://developerdocs.instructure.com/services/canvas/resources/access_tokens)。官方接口存在不等于每所学校的配置均允许当前用户通过自己的 token 调用；真实授权结果以该实例响应为准。
- TC-012 / AC-012：续期前后、尚未接近到期、无到期日、已过期、重启保留短周期、权限拒绝/限流/离线、无法唯一匹配、异常响应、取消及源站隔离；确认只有必要时发出 PUT，正文不含 token 原值或 regenerate。
- TC-013 / AC-001 / AC-009：Today、Timeline、Review 和无搜索结果在中英文、浅深色、940×620 与1280×800窗口下，空状态占满标题下方剩余区域并居中。使用实际窗口截图与新增空状态布局测量验证。

## 0.1.1 持续发布验收

REQ-013 复用 MOD-006 与 IF-004 的发布和更新契约。FUNC-013：本轮将已实现的 token 续期和布局修复发布为 0.1.1 (2)，维持同一 Sparkle 公钥与更新源；公开包版本及签名一致，旧版本可按更新源发现新版。用户本机保持 0.1.0 (1)，检测和安装由用户亲自验证。

TC-014 / AC-013（P1，发布联调）：运行正式构建、自测和打包器；从公开地址回读四个附件，比较 SHA-256、更新签名、ZIP 与 DMG 内容及版本，确认 latest feed 指向 build 2。发布前后只读核对已安装应用的文件指纹。自然自动检查、下载安装和重启未发生时明确标记待用户验证；具体流程与完成边界见 `RELEASING.md`。
