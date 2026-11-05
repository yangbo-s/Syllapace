# 官方课程时间：CMU 公开课表适配器

核查日期：2026-11-05。只读公开学校资源；未使用 Canvas 凭据、用户资料、付费搜索 API 或模型调用。本文中的课时是研究证据，生产代码没有按这些课号硬编码时间。

## 目标与范围

- GOAL-SOC-001：Canvas 缺少每周授课时间时，用同学期、同 section 的官方记录生成可追溯课程日程。
- REQ-SOC-001 / AC-SOC-001：精确核对学期和课号；有多个 section 时不能猜选。有明确共同 `Lec` 时纳入共同 lecture。
- REQ-SOC-002 / AC-SOC-002：读取学校真实教学日期，排除假期和考试周；维持纽约本地时钟和夏令时。
- REQ-SOC-003 / AC-SOC-003：源记录与 occurrence/series 身份稳定，可存档和离线恢复；无 Canvas token 外发。
- CON-SOC-001：使用现有 `HTTPTransport`、`SpreadsheetReader`、`SourceDocument` 和 `AcademicEvent`；不加依赖。
- OOS-SOC-001：不推测教室、recitation 身份、未明确 section 的多选课、mini 学期边界、其他校区时间，也不把往年课表当成本年事实。

## 官方来源与实际观察

[CMU Registrar](https://www.cmu.edu/hub/registrar/courses-and-scheduling/index.html) 将公开 Schedule of Classes 作为选课与课程安排入口。[完整课表入口](https://enr-apps.as.cmu.edu/open/SOC/SOCServlet/completeSchedule) 提供学期 HTML；其 [Fall 课表](https://enr-apps.as.cmu.edu/assets/SOC/sched_layout_fall.htm) 在核查时明确标注 `Semester: Fall 2026`，`Run Date: 05-nov-2026`。文件约 1.58 MB，可不登录直接访问。

每行包含 Course、Title、Units、Lec/Sec、Days、Begin、End、Location。后续行可能省略课号和 section；这是同课同 section 的另一组授课时间。首个院系课程行有时缺少 `<TR>` 起标签，解析器按闭合行读取实际单元格，不依赖浏览器纠错。

[官方星期图例](https://www.cmu.edu/hub/legend.html) 对应 `M T W R F S U`，其中 `R` 是星期四，`U` 是星期日。`TBA` 不转换成事件。地点列仅给城市，不能当作教室号。

| 用户课程 | 官方 section 与时间，America/New_York | 全学期事件数 |
| --- | --- | ---: |
| 18-647 A | A：Tuesday/Thursday 09:30–10:50；Friday 10:00–10:50 | 39 |
| 18-794 A | A：Tuesday 16:00–16:50；Friday 13:00–15:50 | 26 |
| 19-688 A | A：Thursday 18:00–20:50 | 13 |
| 18-749 | 共同 Lec：Monday/Wednesday 17:00–17:50；唯一 A：Monday 18:00–18:50 | 39 |

这些记录都明确标为 Pittsburgh, Pennsylvania。18-749 的共同 `Lec` 可以标为 Lecture，其 A 只标为 Class；其余课程的 A 也不因行顺序猜成 Lecture 或 Recitation。校方/课程 syllabus 若明确角色，上层可以据此进一步细分。

## 真实教学日期

[Academic Calendar](https://www.cmu.edu/hub/calendar/) 链接 [2026–2027 Pittsburgh Class Meeting Days 工作簿](https://www.cmu.edu/hub/calendar/docs/2627-pgh-class-meeting-days.xlsx) 和 [2026–2027 Academic Calendar PDF](https://www.cmu.edu/hub/calendar/docs/2627-academic-calendar.pdf)。工作簿同时包含 Fall 2026、Spring 2027、Summer 2027，提供逐日 Teaching Day、Date、Classes Meet?。

Fall 2026 从 2026-08-24 至 2026-12-04，共 103 个连续自然日。工作日停课为 9/7、10/12–16、11/3、11/25–27；周末也标为 No。用教学日表展开，117 个事件都止于最后上课日，不延伸到 finals。

存在需要保留的细节：工作簿将 11/3 整天标 No，但 [Provost 官方 Democracy Day 页面](https://www.cmu.edu/leadership/the-provost/provost-initiatives-democracy-day) 明确给出 November 3, 2026，只在 17:00 前停课。适配器必须同时核对页面年份、日期和该明确规则，才恢复当日 17:00 及以后开始的会议。若页面失效或更新为另一年，不推测例外，保留工作簿的停课记录。当前这四门课程不含周二晚课，例外页面失败不会改变它们的 117 次结果。

## 接口与持久化约定

MOD-SOC-001 / API-SOC-001：`OfficialCourseScheduleClient.fetch(semester:) async throws -> OfficialCourseScheduleSnapshot`。

- 输入：规范化前可忽略大小写和首尾空白的 `Fall 2026`、`Spring 2027`、`Summer 2027`；缺年或不明确学期拒绝。`supports(canvasHost:)` 只识别学校域名，调用方需用它限制到正确学校。
- 请求：固定官方 HTTPS 主机；并行获取最多 4 MB 的 SOC HTML、最多 2 MB 的 XLSX；Fall 再读取最多 512 KB 的官方例外页。请求不携带 Authorization/Cookie。传输沿用有界、无自动跳转的 `BoundedHTTPTransport`，超时 30 秒。临时工作簿读取后删除。
- 响应：Sendable/Codable 快照保留 semester、sourceURL、calendarURL、exceptionURL、fetchedAt、原始课表行与教学日。
- `meetings(for:)`：课号必须是五位，可带官方分隔符，如 `18-647 A`、`18647-A`。匹配指定 section，并附共同 `Lec`；没有指定时，只有唯一非 Lec section 才自动选入。TBA section 也参与歧义检查，不能因其尚无时间就忽略。
- `sourceDocument(course:)`：稳定 ID `official:cmu:soc:<规范化学期>:<course.id>`；正文包含完整星期、时钟、学期、停课日期和来源链接。hash 不包含抓取时间、课表 Run Date。`kind = external`、`localOnly = true`，已有本地/模型提取流程不会再次组织它。
- `events(for:)`：由真实 teaching days 生成 `.approved`、`.session`，保留 endsAt、sourceURL、sourceID、sourceSeriesID 和 evidence。明显的 Lec 用 `.lecture`，其余 `.classMeeting`。纽约时区按每个日期建立实际时刻，DST 前后 09:30 保持 09:30。
- 异常：学期不符、无匹配、section 歧义、mini、其他校区、无法验证的课表/日历分别报可诊断错误。HTTP/超时失败沿用连接错误；上层应保留已缓存的来源和事件，不删除历史数据。
- 上层负责把 `events(for:)` 保存至 `SourceDocument.meetingSchedule`、缓存重用、与用户编辑和 Canvas/syllabus 来源的优先级处理。快照本身也可 Codable 存档。

ADR-SOC-001：选择公开 Registrar HTML + 教学日 XLSX，而非依赖搜索摘要或再调用模型读取课号。前者明确同学期、section、时间和教学边界，不加凭据或费用；代价是学校网页/工作簿结构变化需要维护。结构、日期或学期不能验证时不生成猜测时间。仅访问静态课表无法获得教室，文档也不声称已获得。

## 验证追踪

| 用例 | 对应要求 | 实际行为断言 |
| --- | --- | --- |
| TC-SOC-001 continuationRowsRetainExactCourseAndSectionWithoutGuessingMeetingRole | REQ-001 | 三门缺失课程、多行 section、上午/下午时钟正确；不猜 recitation |
| TC-SOC-002 onlyAnExplicitCommonLectureAndUniqueSectionAreSelected | REQ-001 | 共同 Lec + 唯一 A；第二个 TBA section 也阻止无 section 自动匹配 |
| TC-SOC-003 wrongSemesterCampusAndMiniSectionsNeverProduceGuessedClasses | REQ-001 | 往年、其他校区、mini、含糊课号拒绝；学校域名边界正确 |
| TC-SOC-004 departmentBoundariesAndUnknownTimesCannotInheritOldSchedules | REQ-001 | 院系切换清空继承；TBA 无事件；缺起始 TR 仍可读取 |
| TC-SOC-005 actualTeachingDatesExcludeBreaksAndExamPeriodAndKeepLocalTimeAcrossDST | REQ-002/003 | 假期不排课、考试周不延伸、DST 正确、ID 幂等 |
| TC-SOC-006 democracyDayEveningExceptionRequiresMatchingOfficialYearAndStatement | REQ-002 | 明确本年官方例外只恢复晚课，17:00 前不恢复 |
| TC-SOC-007 calendarRejectsMissingDatesDifferentTermsAndUncertainCells | REQ-002 | 日期跳跃、年份不符、不明确 Y/No 拒绝 |
| TC-SOC-008 officialSourceHasStableIdentityAndLocalOnlyProvenance | REQ-003 | 正文/链接/稳定 hash、localOnly、Codable 往返 |
| TC-SOC-009 publicRequestsAreBoundedUnauthenticatedAndRejectSemesterRollover | REQ-001/003 | 实际请求无 token，有上限；年度滚动后的 HTML 拒绝 |
| TC-SOC-010 publishedFall2026ScheduleHasAllFourRequestedCourses | REQ-001/002/003 | 显式启用的公开联网合同检查：官方起止日、四课时钟和事件均存在 |

SwiftPM 由主代理统一执行，避免并发构建。离线：`swift test --filter OfficialCourseScheduleTests`；公开网络检查：`SYLLAPACE_TEST_PUBLIC_SCHEDULE=1 swift test --filter OfficialCourseScheduleTests/publishedFall2026ScheduleHasAllFourRequestedCourses`。公开检查默认不运行，防止离线测试依赖网络或未来学期变化；它不需要任何用户凭据。测试执行结果与整合后的最终 100 分证据评分记录在主任务验收中。

主代理已确认原 10 项全部通过，包含约 1.324 秒的公开课表实读。之后 TC-SOC-010 增加 39/26/13/39 次、总计 117 次、每组完整 weekday/start/end、所有停课日无事件和 ID 唯一断言；增强版在获准联网环境重跑通过，约 3.57 秒。普通沙箱的公开网络检查曾因 DNS 不可用失败，未放宽断言，联网环境的重跑覆盖同一测试。隔离真实四课程资料的 CLI `--canvas --official --curate-limit 0` 也确认官方 117 次结果。

## 实际资料审计 CLI

`SyllapaceAudit` 是独立 SwiftPM executable target，不进入应用安装包。`build.sh` 只复制 `Syllapace` 可执行文件进 `.app`。该工具没有访问默认用户资料库、UserDefaults、Keychain、通知或系统日历的代码；所有输入均为显式参数，真实执行和私有输入由主代理准备。

```sh
swift build --product SyllapaceAudit
.build/debug/SyllapaceAudit \
  --archive /tmp/private-audit-input/archive.json \
  --config /tmp/private-audit-input/config.json \
  --credentials /tmp/private-audit-input/credentials.json \
  --output-dir /tmp/private-audit-result \
  --canvas --official --curate-limit 0

# 复用上次完整源缓存，只请求最多 8 份代表性资料。
.build/debug/SyllapaceAudit \
  --archive /tmp/private-audit-input/archive.json \
  --config /tmp/private-audit-input/config.json \
  --credentials /tmp/private-audit-input/credentials.json \
  --output-dir /tmp/private-audit-result \
  --resume --curate-limit 8
```

输入 `config.json` 使用 `canvasHost`，以及可选的 `modelEndpoint`、`modelName`、`modelProvider`（现有 enum rawValue）、`modelWorkspaceID`。凭据支持私有 JSON 中显式 `canvasToken` / `modelKey`，或既有凭据文档的 `values` 字典；不读取 Keychain，不写回凭据。凭据文件必须为本人拥有的普通文件且无组/其他用户权限。输入路径必须是绝对路径，拒绝真实 Application Support/Preferences 目录和符号链接文件。

默认课号为四个目标课程；`--courses` 可传逗号分隔的精确 code，`--semester` 可显式选学期，否则要求输入课程只有一个共同学期。Canvas 使用现有公开 `sync(courses:)` 接口，仅同步这四课；`--file-limit` 限制额外下载的 syllabus/schedule 文件，默认 12，上限 50，已有相同 revision 正文直接复用。没有 `--canvas`、`--official` 且 `--curate-limit 0` 时不发网络请求。

`--curate-limit` 默认 0，上限 40。默认候选是每课一份 syllabus，随后每课一个带相对日期的 announcement，不足四份公告时由其他课程的公告补齐，至多四份 syllabus + 四份公告。重跑仍选择同一批，缓存命中不会悄悄推进到所有剩余资料。可用 `--source-ids` 指定源 ID 做针对性复查；`--retry-failures` 才重试同指纹失败。每次调用都经过 `CurationContext.prepare`，按实际 model identity、完整准备后文本、课程教学边界和时区计算指纹，并写 `SourceCurationRecord`。

官方数据赋给 `source.meetingSchedule`，使用 `EventCuration.reorganize`；官方教学边界保存于来源，审计和应用的 curationWindow 都优先用已验证来源的 `teachingStartsAt` / `teachingEndsAt`，不覆写 Canvas 课程 enrollment 日期。存在官方时间表时不再新生成本地 WeeklySchedule。结果使用同一 `CourseScheduleProjection.project(events:sources:courses:)`，涵盖重复来源合并和有证据的停课通知。

输出目录必须是新目录或显式 `--resume`，权限 0700；`result-archive.json` 包含完整隔离来源、事件、问题和缓存，用于断网复现，`summary.json` 只含源 ID、类型、字数、日期元数据是否存在、问题类别和计数。文件权限 0600，不写凭据。每次成功或失败组织均立即 checkpoint，避免中断后重复调用。私有结果仅放 `/tmp`，不能提交、打包或放入安装包。

stdout 只给安全课号、Canvas/model/local/official 事件计数、会议数、`course + start + kind` 重复课次数、需要补充的数量和安全错误类型；不输出正文、资料标题、原始 API 错误或密钥。审计用的 source cache 与线上应用数据完全分开。

## Canvas 原生 recurring 身份

实际审计另发现原生 calendar 导入没有保留 recurring 身份。[Canvas Calendar Events 官方协议](https://k12.instructure.com/doc/api/calendar_events.html) 的 `series_uuid` 标识服务器返回的 recurring series，`rrule` 描述重复规则。两条 Canvas 导入路径现在都把非空、最长 128 字节且只含 ASCII 字母/数字/下划线/连字符的 series_uuid 保存为 `canvas-series:<course.id>:<series_uuid>`。相同 UUID 在不同课程仍是不同系列；不存在 UUID 时不根据标题或 RRULE 编造真实系列，不自行展开 RRULE。

`CanvasRecurringSeriesTests` 的 mock 检查两条 sync 路径、课程隔离、重复稳定及异常值。服务端返回三次课、规则 COUNT=1000 时仍只导入三次；五组空白/异常长度/分隔符输入不丢失原始课次，只不创建 series 身份。该新增测试由主代理统一执行。

若学校未返回 series_uuid，可以在展示层对同课程、同会议类别、同本地星期/时钟的实际观察分组，保留逐次真实日期和缺口。这样的 UI 分组不能写成官方 recurrence、创建新 occurrence 或推断被取消的课次。
