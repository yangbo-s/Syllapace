# Syllapace

[English](README.md) | **简体中文**

原生 macOS 应用，用于整理 Canvas 作业和课程大纲中的截止日期，支持本地存储、桌面卡片和 Apple Calendar 同步。

Syllapace 在你的 Mac 上运行。连接自己的 Canvas 账号，按需配置自己的模型 API key，对照原文审核提取的日期，再将已确认的日程同步到 Apple Calendar。小巧的桌面卡片让近期任务随手可见。

目前是早期版本。项目已提供自动化测试和本地应用检查；本轮开发尚未使用真实 Canvas 账号、模型服务和已授权的 Apple Calendar 连接进行联调。具体验证状态见[验收证据](docs/ACCEPTANCE.md)。

## 安装

从 [GitHub Releases](https://github.com/yangbo-s/Syllapace/releases) 下载 **DMG**，将 Syllapace 拖入 Applications，再从那里打开。首个版本支持 **Apple Silicon 和 macOS 26+**，同时提供 ZIP 和 SHA-256 校验值。

安装包使用 ad hoc 签名，**尚未经过 Apple 公证**。如果 macOS 阻止首次启动，请核对来源和校验值后，通过 Apple 的 **系统设置 → 隐私与安全性 → 仍要打开** 流程允许此应用启动，详见[发布说明](docs/releases/0.1.0.md)。更新签名可保护后续下载，但不能替代 Apple 公证。

## 语言与更新

在 **设置 → 通用** 中选择 **跟随系统**、**English** 或 **简体中文**。应用界面会立即切换并记住偏好；原生系统菜单和 Sparkle 更新窗口会在重新打开后采用所选语言。Canvas、OpenAI、API、PDF、DOCX、ICS 等产品与协议名称保留原文。课程名称和原始证据不会翻译；切换界面语言不会扩展文档解析器支持的语言范围。

选择 **Syllapace → 检查更新…**，或使用通用设置中的按钮。Sparkle 会检查托管在 GitHub 上的更新源，用应用内置的公钥验证更新包，并在确认后安装。可在通用设置中关闭自动检查。更新检查不发送课程内容或凭据，系统配置报告也已禁用。

## 构建与运行

环境要求：

- macOS 26 或更高版本。
- Xcode 26 或更高版本，包含 Swift 6.2+ 工具链和 Apple 资源编译工具。仅安装 Command Line Tools 时，可能会选用较旧的 Swift 版本。
- Swift Package Manager 会下载锁定版本的 Sparkle 2.10.1 依赖。无需托管 Syllapace 服务。

在仓库根目录运行：

```sh
./build.sh --open
```

脚本会生成 `build/Syllapace.app`，嵌入 Sparkle 和本地化资源，编译图标，并默认使用 ad hoc 签名。开发时可运行 `./build.sh --debug --open` 加快构建。默认使用 `/Applications/Xcode.app` 中的工具链；如 Xcode 安装在其他位置，请设置 `DEVELOPER_DIR`。如需使用本机已有的合适签名身份，可设置 `SIGN_IDENTITY`。此构建不包含公证。更新包签名、打包和发布流程见[发布维护](docs/RELEASING.md)。Fork 维护者需要使用自己的更新源和更新签名密钥。

如需使用虚构课程和截止日期查看界面：

```sh
./tools/demo.sh
```

演示日程仅在内存中生成，不会保存到你的真实资料库。演示模式下禁用 Canvas、模型提取、EventKit 访问和更新检查。退出演示后，正常打开应用即可配置自己的工作区。

## 从课程大纲开始

1. 选择 **文件 → 导入课程大纲…**（`⌘O`），导入前选好课程和学年。
2. 导入文本型 PDF、DOCX、UTF-8 TXT、Markdown 或 HTML 文件。[`fixtures/syllabus.md`](fixtures/syllabus.md) 提供了一份虚构示例。
3. 打开 **待审核**，核对原文证据，补全尚未确定的日期，再逐项确认或拒绝候选日程。
4. 已确认的日程会出现在 **今天** 和 **时间线**。可按日程或课程搜索、按课程筛选，并将任务标记为完成。
5. 在 **来源** 中查看导入的文本，或主动发起模型提取。

规则提取会保留只有日期、没有时间的日程，并将有歧义的日期留待确认。一个句子包含多个日期时，不会直接假定其中某个就是正确的截止日期。学年由导入设置指定。来源发生变化时，会产生待审核的冲突，不会静默覆盖已确认的日期或用户修改。

## 连接 Canvas

打开 **设置 → Canvas**：

- 输入学校的 Canvas 地址，例如 `https://canvas.example.edu`。只填写源站地址，不要附带课程路径、查询参数或 URL 中的凭据。
- 粘贴自己的 access token，点击 **保存连接**，再点击 **立即同步**。保存时检查输入格式；同步时向 Canvas 验证访问权限。
- 保持所保存地址的写法一致。凭据按配置的地址存入 macOS Keychain。更改地址后，需要为新地址保存 token；已有 token 不会自动转移到另一个端点。
- token 输入框留空时，会保留当前地址已保存的凭据。

连接器读取当前活跃课程、作业及提交状态、课程日历事件、课程大纲 HTML 和可访问文件的元数据。可能属于课程大纲或日程安排的文档会显示在 **来源** 中，选取后下载。它不会遍历所有课程附件，也不会修改 Canvas 中的课程内容。

**运行时每 10 分钟刷新** 需要主动开启，应用必须保持运行才能获取变更。部分请求失败时会保留现有数据，同步提示会指出哪些课程资源获取失败。token 过期后可在设置中更换。后台刷新会跳过哈希值未变化的课程大纲，也不会切换当前页面。

当前源码构建的 Canvas 设置中，**自动续期 token** 默认开启；v0.1.0 下载包尚不包含此功能。应用运行时会检查已保存的个人 token，在有效期末段向学校请求延长到期时间。续期周期不超过首次确认的有效期，最多 30 天；仅更新原 token 的到期时间，其值和权限不变。设置中显示有效期或处理提示，可随时关闭自动续期。如果应用一直关闭直到 token 过期，或学校拒绝续期，请在 Canvas 重新生成并保存。续期失败不影响课程同步或已保存资料。

## 使用自己的模型

打开 **设置 → 提取**，填写：

- HTTPS API base URL，例如 `https://provider.example/v1`。
- 服务提供方使用的准确 model identifier。
- 你的 API key。

适配器使用兼容 OpenAI 的 **chat completions** 端点。如果提供的基础路径尚未包含 `/chat/completions`，会自动追加。服务需要支持 JSON 响应格式、`temperature` 和 `max_tokens`；无法保证兼容每一种服务或模型。此适配器不支持 HTTP 端点，包括普通的本地 HTTP 模型服务。

对单个来源点击 **提取**，才会将该文档的文本直接发送给配置的服务。提取不会自动执行。API key 存储在 Keychain 中，并按配置的端点隔离。文档请求不包含 Canvas token，也不会向模型提供工具。响应会经过结构校验，并与文档中的实际证据片段匹配，随后统一进入待审核。片段匹配并不代表模型正确理解了日期，请在确认前检查候选日程。模型调用可能产生费用，由你自己的服务账号承担。

## Apple Calendar

打开 **设置 → 日历 → 连接并同步日历**。Syllapace 会请求完整日历访问权限，以便找到和更新之前写入的日程，并检测外部修改。实现中只操作专用的 `Syllapace` 日历及其拥有的日程。

当前实现仅使用本地 **On My Mac（在我的 Mac 上）** 日历。如果本地来源不可用，请先在 Apple Calendar 中选择 **File → New Calendar → On My Mac**，再重新连接。它不会静默创建 iCloud 日历，也不会托管订阅 URL。

- 只有已确认且日期、时区有效的日程会发布到日历。
- 重复同步会复用已有日程映射。确认日期变更后，会更新原有日程。
- 在外部编辑或删除日程会产生冲突。选择 **使用 Syllapace 版本** 后，需要明确确认，才会覆盖外部修改或重新创建已删除的日程。Calendar 中的编辑不会自动反向导入 Syllapace。
- 拒绝先前已发布的日程时，若对应的 Calendar 日程未被外部修改，可以一并移除。来源缺失或获取失败不等于删除。
- **自动同步已确认的变更** 需要主动开启，并仅在应用打开时运行。退出 Syllapace 后，已保存的日程仍会留在 Calendar 中。

还可通过文件菜单（`⇧⌘E`）或日历设置导出通用的 `.ics` 文件。导出的是当前快照，不会持续同步；即使 UID 保持稳定，接收端在重复手动导入时仍可能产生重复日程。

## 桌面卡片与快捷键

使用 `⇧⌘D` 或菜单栏项目显示桌面卡片。拖动卡片背景可调整位置，切换图钉可让卡片保持在其他窗口上方，点击日程可打开时间线。桌面卡片使用 AppKit 面板实现，不是 WidgetKit 扩展。

| 操作 | 快捷键 |
| --- | --- |
| 新建日程 | `⌘N` |
| 导入课程大纲 | `⌘O` |
| 同步 Canvas | `⌘R` |
| 导出 ICS | `⇧⌘E` |
| 显示桌面卡片 | `⇧⌘D` |
| 设置 | `⌘,` |

## 数据与隐私

资料库以 JSON 归档保存在 `~/Library/Application Support/Syllapace/archive.json`，采用原子写入。`archive.json.backup` 保留上一份可读取的归档。EventKit 绑定单独存储在同目录的 `calendar-mapping.json` 中。凭据存入 Keychain；连接地址和非敏感偏好存入 UserDefaults。

导入文本和证据保存在本地，未额外进行应用层加密。本地原始文档仍保留在你选择的位置，下载的临时文件在导入后清理。无需 Syllapace 账号、遥测服务或后端。发起模型请求时，会将选中来源的文本发送给你配置的服务。

开发时可用 `APP_STORE` 指定另一个归档路径，隔离数据。如果归档损坏或使用未知结构版本，应用会提示并拒绝覆盖。手动恢复文件前，请备份应用支持目录；不要随意丢弃日历映射文件，它用于保留日程归属关系并防止重复创建。

## 验证

运行应用级脚本前，请先构建：

```sh
./tools/test.sh        # Swift Testing：领域模型、文档、连接器、日历同步规划器
./tools/selftest.sh    # 在临时存储中验证应用的导入、审核、变更和持久化流程
./tools/snap.sh        # 使用虚构数据捕获应用的浅色和深色界面
./tools/grid-lint.sh   # SwiftUI 间距检查
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift tools/check-layout.swift .impeccable/review/*-layout.json
```

截图和实际窗口布局测量数据写入 `.impeccable/review/`。运行 `tools/snap.sh` 时设置 `APP_LAYOUT_ONLY=1`，可仅刷新测量数据，不覆盖截图。原生设置表单使用系统布局，不进行布局探测；检查器测量自定义内容、检查器面板、导入与编辑表单，以及桌面卡片。截图脚本捕获应用自身的窗口。准确捕获窗口可能需要屏幕录制权限；日志中的 `view-render fallback` 不代表已验证原生材质或活动窗口外观。

测试使用合成的 PDF/DOCX 文档、模拟网络响应和日历快照，不会索取真实凭据或写入你的实际日历。参见[工程需求](docs/ENGINEERING.md)、[EventKit 决策](docs/decisions/0001-apple-calendar-eventkit.md)和[验收证据](docs/ACCEPTANCE.md)。

## 当前限制

- 导入上限：每份文档 20 MB、PDF 最多 150 页、提取文本最多 2 MB。扫描件或纯图片 PDF 需先在其他工具中进行 OCR。复杂 PDF 排版可能导致阅读顺序丢失；DOCX 解析保留基本的行列关联，不复现视觉排版。
- 模型提取最多接受 64,000 个 Swift 字符串字符的来源文本，并返回最多 300 项候选日程。此功能可选，需要兼容的 HTTPS 服务。
- 文件发现依赖课程大纲或日程安排类文件名，文件需要明确导入。已下载的 PDF/DOCX 不会在每次 Canvas 刷新时自动重新下载；请重新导入修订后的文件来审核变更。
- 规则提取较为保守，主要处理英文教学日程表述和明确日期，并非完整的多语言日期解析器。
- 来自不同来源的相似标题会标记为待审核；应用无法证明名称不同的两个教学节点是同一项日程。
- 应用没有独立后台代理、OAuth 配置、OCR、Windows 构建或其他 LMS 集成。
- 运行时权限流程、具体账号的 Canvas 权限、模型服务兼容性和真实 Calendar 同步，仍需用户配置后进行实际验证。

## Logo

课程页面与日期标记组成的标志提供透明 [SVG 文件](Brand/README.md)，包含双色、青绿、近黑和白色版本。[构造图](Brand/concepts-v2/alignment.png)记录了对齐网格。原生应用图标在 `Icon/AppIcon.icon` 中使用相同路径，由 macOS 提供材质和外观变体。

## 项目结构

`Sources/SyllapaceKit/` 包含领域模型、持久化、解析、变更协调、连接器、ICS 导出和不执行外部写入的日历同步规划器。`Sources/Syllapace/` 包含 SwiftUI 视图、应用状态、桌面面板和 EventKit 适配器。`Tests/SyllapaceKitTests/` 使用合成测试样例验证核心模块边界。

桌面交互借鉴了 [Still Today](https://github.com/OyangDer/still-today)。这是全新的原生 Swift 实现，未嵌入上游的 Svelte/Tauri 界面。
