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

IN-001：Canvas HTTPS host + PAT；模型HTTPS endpoint + key + model；用户选择文档（UTF-8文本、PDF、DOCX）。密钥仅Keychain。
OUT-001：版本化本地归档、候选/确认事件、系统日历、ICS文件。网络/解析错误向用户显示，不清空已有数据。
CON-001：macOS26+，Swift6，SwiftUI+AppKit，用户自行运行，无后端。真实Canvas/BYOK/EventKit联调需用户配置，仅以合成数据自动测试。
ASM-001：默认系统时区，导入时明确学年；无法解析日期保留待审核。应用内文案英文，工程交流中文。
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

契约、模块实现、合成数据集成、构建与自动化检查已有证据。真实窗口视觉问题已经修正；外部服务和系统权限联调尚未跨越最终发布门禁，详见 `ACCEPTANCE.md`。本次交付为本机可运行实现，未声称公开发行就绪。当前包 ad hoc 签名，不包含公证或安装器；源码、构建脚本、测试、示例、设计文档和验收记录一并交付。
