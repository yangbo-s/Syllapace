# Canvas 内容覆盖、学期范围与同步语义研究

> 历史研究记录：以下“当前实现/尚未实现”以 0.1.1 源码为基线。后续 0.2.0 已落实学期选择、原生来源扩展、分类和连接修复；最终覆盖与未验边界见 [0.2.0 发布说明](../releases/0.2.0.md) 和 [验收记录](../ACCEPTANCE.md)。

研究日期：2026-11-04。范围：官方 API 文档、服务商官方说明、本仓库当前实现，以及经用户授权的课程学期/token 元数据只读核对。账户查询结果仅用于当前会话诊断，本文不保存真实课程、账户、学校数据或凭据，也不将单个账户的结果推广为全部 Canvas 实例的行为。API 存在表示有可实施路径，不表示每个学校、课程和学生角色都具有访问权限。本文为研究和设计建议；未修改产品代码，也未发送 token 延期请求。

## 结论

应先确定用户选择的学期和课程，再同步这些课程的内容。Canvas 的内容来源与日程类型需要分开建模：Announcement 是信息来源，Project 是学业事项；一条 Announcement 可以同时提供上课调整、作业延期和 schedule 链接。来源数量的增加必须配合身份关联、日期语义和范围控制，否则会增加重复和错误日程。以下实现顺序与模型均为基于研究的建议，尚未实现。

## Token 维护

需要区分三种行为：

| 行为 | 结论与依据 |
| --- | --- |
| 持续使用手动生成的 PAT | 不会自动滑动延期；上游 `AccessToken#used!` 更新使用时间，不延长永久有效期。[AccessToken 源码](https://github.com/instructure/canvas-lms/blob/master/app/models/access_token.rb) |
| 应用主动延长 PAT 到期时间 | 官方 `PUT /api/v1/users/:user_id/tokens/:id` 接受 `token[expires_at]`。不传 `regenerate` 即不请求更换 token 字符串；成功与否仍受实例权限和到期策略约束。[Access Tokens](https://developerdocs.instructure.com/services/canvas/resources/access_tokens)、[TokensController](https://github.com/instructure/canvas-lms/blob/master/app/controllers/tokens_controller.rb) |
| OAuth refresh | 使用 `POST /login/oauth2/token` 和 `refresh_token`、应用凭据换取新的 access token；手工 PAT 不能作为 OAuth refresh token 使用。[OAuth endpoints](https://developerdocs.instructure.com/services/canvas/oauth2/file.oauth_endpoints) |

读取本人 token 元数据的权限与修改权限并不相同，因此 GET 成功不能证明 PUT 可延期。过期的 PAT 也不能再用自身的已失效认证完成延期；需要在失效前成功执行维护。[AccessToken 权限规则](https://github.com/instructure/canvas-lms/blob/master/app/models/access_token.rb)

现有 [CanvasClient.swift](../../Sources/SyllapaceKit/CanvasClient.swift#L175) 已实现枚举、唯一识别、临近到期时 PUT、检查服务端新到期时间的流程；[CanvasTokenLease.swift](../../Sources/SyllapaceKit/CanvasTokenLease.swift) 将本地计划周期上限设为 30 天，并在剩余时间进入 `min(7 天, 周期 / 4)` 时尝试延期。[CanvasTokenRenewal.swift](../../Sources/Syllapace/CanvasTokenRenewal.swift) 只在应用进程运行时调度检查，不能保证关机或长期未启动期间也能维护。

当前诊断不足：无法唯一匹配 token、workflow/date 校验失败、服务器拒绝 PUT、新日期未延长，均可能显示相同的“暂不可自动续期”。该文案不能证明学校禁止延期，也不能证明 token 已被自动续过。后续应分别呈现到期时间、最近检查、最近成功延期，以及识别失败/权限不足/网络失败；诊断记录只保留阶段与非秘密校验结果，不记录 token 或 hint 原文。

只读核对发现了可定位的兼容性缺口：实例未返回 `token_hint`，而 `visible_token` 未匹配客户端当前支持的两种“前 5 字符 + 省略号”形式。应先确认并兼容服务端掩码格式、唯一识别当前凭据，再验证延期权限；不能因为列表只有一条记录就直接把它当作当前 token 执行 PUT。本轮没有验证服务器是否接受新的到期时间。

## 学期与课程范围

`enrollment_state=active` 表示 enrollment 状态，不等于用户选择的 Fall 2026。学生课程接口 `GET /api/v1/courses?include[]=term` 可返回 `enrollment_term_id` 和 term 的名称、开始、结束；应以此建立学期列表，再在客户端选择和过滤。不要将账号管理员课程查询接口的参数直接套到学生课程接口。[Courses](https://developerdocs.instructure.com/services/canvas/resources/courses)

不能要求学生 token 先调用账号级 `GET /accounts/:account_id/terms`：当前官方文档要求查看者至少在一门课程有 active teacher enrollment，管理则需要账号管理权限。学生端从自己可访问的 courses 推导 term，缺失项允许本地补充。[Enrollment Terms](https://developerdocs.instructure.com/services/canvas/resources/enrollment_terms)

建议交互与保存规则：

1. **先发现，后同步。** 首次连接仅获取课程及学期元数据，展示 `Fall 2026` 等学期，再由用户确认课程清单。尚未选择的课程不抓正文、不抽取、不导出。历史学期的发现需要另外读取自己有权访问的已完成课程，不能永远只查 active。
2. **稳定标识。** 保存 Canvas origin + term ID + course ID，不以显示名称作为主键。不同 Canvas term（例如 full semester 和 mini term）允许映射到同一个本地学期分组；同名学期也不能无条件合并。
3. **明确归属优先。** 已有 term 归属优先；课程名称、起止时间只用于推荐，不能据名称中的年份或事件日期自动确认。未知、Default Term、跨学年资源、Portal/Orientation 单独列出供用户选择，不自动混入学期课程。
4. **视图一致。** 选定学期和课程同时约束 Today、Timeline、Review、搜索、课程侧栏、桌面视图、来源发现，以及 EventKit 新增输出。保留“全部学期”入口，但不默认展示所有历史内容。
5. **归属与日期分开。** Fall 课程的补交截止可能在学期末之后；不能按日期硬切掉仍属于该课程的任务。上课周期和公告检索窗口需要明确边界，开学前发布的 syllabus/公告也不能只因发布时间在学期前而丢弃。
6. **无损迁移。** 旧 archive 中的课程通过已有 Canvas course ID 补齐 term 和用户选择状态；未知项不删除。切换学期仅改变视图与后续同步集合，不能静默删除历史数据或 Apple Calendar 中已写入的日程；日历清理作为独立的明确操作。

以上为建议，尚未实现。当前模型只保存课程 id/name/code/color，没有学期字段；仅增加一个前端下拉框无法补齐这些范围约束。

## 官方能力矩阵

以下路径除 New Quizzes 外均以 `/api/v1` 开头。所有列表都应处理分页，按资源记录权限失败，避免某个可选来源失败使整门课同步失败。

| 来源 | 读取入口与有用内容 | 权限、语义与覆盖边界 |
| --- | --- | --- |
| Inline syllabus | `GET /courses/:course_id?include[]=syllabus_body`；HTML 正文 | 保留 HTML 中的链接、表格和证据位置。`syllabus_body` 与 course 的 term/timezone 等字段有官方定义。[Courses](https://developerdocs.instructure.com/services/canvas/resources/courses) |
| Assignments | `GET /courses/:course_id/assignments?include[]=submission`；描述、个人适用截止日期、assignment group、submission 类型和 quiz 关联 | `due_at` 已按请求用户的 override 计算。`unlock_at`/`lock_at` 是可访问时段，不能代替截止日期；`quiz_id` 对应 Classic Quiz，`is_quiz_assignment` 指 quiz LTI assignment。Canvas 没有统一的 Project 实体字段。[Assignments](https://developerdocs.instructure.com/services/canvas/resources/assignments) |
| Announcements | `GET /announcements?context_codes[]=course_<id>&start_date=...&end_date=...`；正文、附件、schedule 外链 | 默认只从 14 天前开始，`end_date` 默认是起点后 28 天。多个课程合并请求时任一课程没有 View Announcements 权限会使调用失败，因此建议按课程隔离。未发布/未来通知受到权限限制。[Announcements](https://developerdocs.instructure.com/services/canvas/resources/announcements) |
| Announcement / Discussion 正文 | `GET /courses/:course_id/discussion_topics` 及单条详情；`message` HTML、`attachments`、`assignment_id` | 有评分的 Discussion 应关联 assignment，不能再复制为一项作业。公告发布日期是来源时间，不是正文提及事项的日期。[Discussion Topics](https://developerdocs.instructure.com/services/canvas/resources/discussion_topics) |
| Classic Quizzes | `GET /courses/:course_id/quizzes`；标题、说明、due/unlock/lock、time_limit、quiz_type | 以当前用户可见资源为限。通过 Assignment 的 `quiz_id` 关联；练习 Quiz 未必有评分 Assignment。考试持续时间与开放窗口不同。[Quizzes](https://developerdocs.instructure.com/services/canvas/resources/quizzes) |
| New Quizzes | `GET /api/quiz/v1/courses/:course_id/quizzes` 或 `.../:assignment_id`；独立 API 返回 NewQuiz 信息 | 官方有 API，不能称“无法接入”。但已查文档没有承诺学生角色可读全部设置，需后续能力探测。基础截止日期优先从关联 Assignment 获取；New Quizzes 会在 Assignments 中显示。[New Quizzes API](https://developerdocs.instructure.com/services/canvas/resources/new_quizzes)、[官方产品说明](https://community.instructure.com/en/kb/articles/662768-what-is-new-quizzes) |
| Calendar events | `GET /calendar_events?type=event&context_codes[]=course_<id>&start_date=...&end_date=...`；开始、结束、地点、全天、周期信息 | `all_events=true` 会忽略日期边界。`type=assignment` 是 Assignment 的日历投影，应关联原作业；section 子事件和隐藏父事件不能双重展示。Calendar 里没有内容不等于课程没有上课安排。[Calendar Events](https://developerdocs.instructure.com/services/canvas/resources/calendar_events) |
| Submissions / Grades | `GET /courses/:course_id/students/submissions`；不指定 student_ids 时返回当前用户的提交；也可使用 Assignment 的 submission | 学生只能列自己的提交。保留 `workflow_state`、submitted_at、late、missing、excused、grade、score、grade_matches_current_submission 等实际返回字段；无成绩不能推断为 0 分。成绩属于作业状态，不应转换成日历事件。[Submissions](https://developerdocs.instructure.com/services/canvas/resources/submissions) |
| Modules | `GET /courses/:course_id/modules`，再 `GET /courses/:course_id/modules/:module_id/items` | 类型包括 File、Page、Discussion、Assignment、Quiz、ExternalUrl、ExternalTool。可发现正文和附件的引用；`include[]=items` 可能省略大模块的 items，不能据此判为空。遵守 lock 信息与学生可见范围。[Modules](https://developerdocs.instructure.com/services/canvas/resources/modules) |
| Pages / front page | `GET /courses/:course_id/front_page`、`GET /courses/:course_id/pages`、`GET /courses/:course_id/pages/:url_or_id` | 单页返回 HTML `body`，列表可选包含；应优先跟随 Modules、syllabus、announcement 已引用的 Page。页面历史 API 要求编辑权限，学生端历史变更应依赖本地快照。[Pages](https://developerdocs.instructure.com/services/canvas/resources/pages) |
| Files / 附件 | `GET /courses/:course_id/files`；根据明确引用读取文件详情/下载 | Files 列表与具体附件是不同资源入口；文件包含 `locked_for_user`、`hidden_for_user` 与 visibility 信息。目录不能列举时可以尝试正文/Modules 的明确可见引用，但目标仍需单独通过权限检查，不能声称绕过 403。[Files](https://developerdocs.instructure.com/services/canvas/resources/files) |

## 外链与第三方 integrations

**Google Sheets。** “Publish to web” 会生成可分享的已发布网址；可将此类公开的 schedule 作为外部来源读取。普通共享网址不能直接假定无需登录。私有表格通过 Google Sheets API 读取需要 Google 的授权范围；Canvas token 不是 Google 凭据。第一阶段建议支持公开表格/已发布导出链接及用户手动导入；需要登录时保留原始链接并清楚标记尚未读取，不把登录页当作课程内容。不得因为 app 需要读取就替用户公开或改变表格权限。[Google 发布说明](https://support.google.com/docs/answer/183965?hl=en)、[Sheets API 授权](https://developers.google.com/workspace/sheets/api/scopes)

**Gradescope。** 可先消费 Canvas 中已关联的 Assignment 和回传到 Canvas 的成绩。官方 LTI 1.3 说明明确：个人 extension、late due date 不同步到 Canvas；due date 是否同步取决于学校设置；grade passback 只传整体 raw score，题目分数、rubric、feedback 与批注留在 Gradescope。因而此方案覆盖 Canvas 侧可见信息，不能承诺完整 Gradescope 同步或第三方个人延期的准确覆盖。[Gradescope 官方 Canvas LTI 1.3 指南](https://guides.gradescope.com/hc/en-us/articles/23586543164173-Using-Gradescope-LTI-1-3-with-Canvas-as-an-instructor)

**Piazza。** 官方 Canvas 指南描述通过 LTI External Tool 添加到导航或 Module 的流程。发现这个链接只能证明课程使用 Piazza；不能推出 Canvas 的 REST token 可以读取 Piazza 帖子。首期保留可打开的入口；完整内容读取作为独立 connector 研究，当前没有已核实的通用学生 API 方案。[Piazza 官方 Canvas 集成说明](https://support.piazza.com/support/solutions/articles/48001065444-configure-piazza-within-canvas)

## 建议的数据模型与关联规则

以下是产品设计建议，并非 Canvas API 自身保证。

1. **范围。** `Term → selected Course → Source → Academic item`。课程选择控制同步、抽取、主界面和 EventKit 输出；仅在最终 UI 隐藏不够。用户切换学期应切换视图和同步集合，不删除历史资料。
2. **类型。** 用上课安排（Lecture/Lab/Discussion 等有开始结束的 session）、作业、Project/里程碑、Quiz/Exam、Presentation、其他事项区分日程。Source kind（announcement/page/file/assignment/external link）独立于 item kind。Project 根据 assignment group、明确标题/描述、用户修正判定，并保留分类依据与置信度；不能将所有 Assignment 默认为 homework。
3. **时间。** 分开存储 startsAt/endsAt、dueAt、availableFrom/availableUntil、recurrence、timezone 和 dateOnly；没有具体时刻不能补造 23:59。上课周期要受选定学期范围约束；教学日历的假期和例外必须显式处理。
4. **身份去重。** 主键使用 Canvas origin/account scope + resource type + resource ID。Module 对 Assignment/Quiz 的引用、Calendar 的 assignment 投影、graded Discussion 等优先通过原生 ID 合并；同名不同周次不能仅按标题合并。不同来源提供的相同事件保留多条证据，非结构化语义匹配只产生可审阅的候选。
5. **变更冲突。** 结构化个人 due_at 是主日程依据，但新公告可能比尚未更新的 Assignment 更及时；有冲突时同时展示来源时间、原文和两个日期，避免模型静默覆盖。用户明确修正的结果不能被下一次同步直接抹掉。
6. **成绩与完成状态。** Submitted、Graded、Excused、Missing、Late 分开存储，避免单个 `completed` 布尔值丢失语义。LTI 没有同步某字段时显示未知，而非推断为未提交或未完成。

## 建议的链接与内容发现流程

1. 先从选定课程获取轻量元数据、Assignments、Calendar、inline syllabus、Announcements、Modules；补充相关 Pages 与 front page。
2. 解析 HTML 时同时生成可读文本和链接表，保留 anchor text、href、来源资源 ID、证据附近文本、HTML/内容 hash。`schedule` 链接的 anchor text 本身不足以抽取表格。
3. 按链接类型路由：同源 Canvas Page/File/Assignment/Quiz 使用相应 API；公开外部文档通过无 Canvas Bearer 的下载器获取；ExternalTool/需要登录的外链保留入口和可见状态。已有下载器“Bearer 仅初始同源请求、重定向不继承”的原则应保留。
4. 限制深度、链接数量、文件大小和请求并发，URL 归一化后记录 visited set，防止循环；不能把任意课程链接扩展成无界爬取。Google Sheets 保留 spreadsheet ID 与 gid；认证或签名 URL 的秘密参数不进入日志。
5. 每个来源保留成功/无内容/权限不足/暂时失败/需外部登录状态。一个 Files 403 应描述为该课程文件目录不可访问，不能升级为整个 Canvas 连接失败。
6. 公告初次读取显式覆盖相关课程时间区间。后续不能只按“发布时间大于上次同步”拉取，否则旧公告内容编辑会漏掉；周期性重新获取范围内的相关来源并比较 hash。页面与外部 schedule 同样保留本地版本和抓取时间。

## 本仓库当前差距

以下为源码观察，不代表本轮已经完成修改：

- [CanvasClient.swift:203](../../Sources/SyllapaceKit/CanvasClient.swift#L203) 的 `sync()` 枚举所有 `enrollment_state=active` 课程；`CanvasCourseDTO` 没有 term、课程开始结束日期或选课范围。
- [CanvasClient.swift:226](../../Sources/SyllapaceKit/CanvasClient.swift#L226) 已读取 Assignments 和个人 submission，但 DTO 只有名称、due_at、submitted_at、excused；全部使用默认 `.assignment`，未保留描述、quiz 关联、assignment group 和完整状态。
- [CanvasClient.swift:238](../../Sources/SyllapaceKit/CanvasClient.swift#L238) Calendar 使用 `all_events=true`，只保留开始日期并设为 `.other`；未保存结束、地点与周期。
- [CanvasClient.swift:251](../../Sources/SyllapaceKit/CanvasClient.swift#L251) 仅从 Files 目录按文件名识别 syllabus/schedule；尚无 Announcement、Module、Page 或正文链接发现。
- [CanvasClient.swift:305](../../Sources/SyllapaceKit/CanvasClient.swift#L305) `plainText()` 直接删除 HTML 标签，`href` 不进入 `SourceDocument`；这会遗漏正文中的 schedule/附件地址。
- [Models.swift:3](../../Sources/SyllapaceKit/Models.swift#L3) 尚无 term、class session、quiz、开始结束/周期模型；来源只保存单一 URL/纯文本，不能表达多来源引用。

## 建议分阶段验收

| 阶段 | 可观察的验收行为 |
| --- | --- |
| 1. 范围 | 用户选择指定学期后先看课程清单；未选课程不参与同步、日期抽取或 EventKit 新增导出；无学期/长期课程单独可选，切换不丢历史。 |
| 2. Canvas 原生来源 | 公告正文和 schedule 链接可追溯；Module→Page→File 引用可发现；某课程目录 403 不阻断其他来源；不将公告发布日误当截止日。 |
| 3. 类型与去重 | 同一 Quiz 在 Assignment/Module/Calendar 出现时只形成一个事项；Project 可独立筛选；上课时间保留起止与周期，日期变更产生冲突提示。 |
| 4. 外链与状态 | 公开表格能读取实际单元格内容；私有表格标记需登录；Gradescope 只承诺已同步到 Canvas 的字段；不将缺失分数、提交状态或第三方延期误判。 |

本研究只为上述实现提供事实与验收依据；没有执行用户学校的各来源权限探测，因此无法宣称其每门课的 Announcement、Page、Quiz 或外链都已经可读。
