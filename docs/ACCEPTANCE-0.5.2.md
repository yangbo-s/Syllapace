# 0.5.2 课程导入验收

对应 [计划](PLAN-0.5.2.md) R521–R526。真实资料的核验使用 `/tmp` 下权限 0700 的隔离目录；输入与结果文件 0600。未覆盖实际安装、凭据、资料库、更新计时或偏好。正文与凭据不进入 Git、安装包或公开报告。

## 根因与改动

公告 DTO 原先没有保留 posted_at，模型无法把 today 对齐到发布日；作业 due/unlock 已经由 Canvas 返回，但没有作为文档提取证据传入模型。现在保留这些元数据，并使用同课程、同任务或同日课次的有出处上下文。明确相对日期公告还可本地恢复精确课次；不将导入时间当事件日期，不把日期不明的课次设成全天占位。

旧资料有 30 条未经用户编辑的冲突，实际只是给既有开始时间补上结束时间。迁移只自动修复这个狭窄场景，保留真正改期、用户修改、撤销与拒绝。相同 Canvas 日历事件被再次从正文提取，加上全局 calendar ID 与课程级 source ID 差异、Zoom 地点描述详略不同，导致重复；现在按源事件身份合并，跨来源同一次课保留关联证据。合并后编辑/取消使用稳定 alias ID，不能令旧副本重新出现。

官方课表检索严格匹配 CMU Pittsburgh、学期和 section，使用官方教学日历排除停课日及考试周。源表未公布完整时间时不替换其他已知周课表。课表和教学边界缓存到 archive；与 model fingerprint 分离，不重新请求模型来生成已验证的官方课次。

## 需求与用例追踪

| 需求 / 用例 | 验证范围 | 结果 |
| --- | --- | --- |
| R521 / TC521 | Canvas metadata、同课程证据、相对日期、发布时区、不同 Part/冲突日期隔离 | CanvasContextTests、CurationContextTests、LocalCurationRecoveryTests |
| R522 / TC522 | dotted AM/PM、英文日月、ISO release、DST/数字日期歧义 | DateEvidenceRegressionTests、Extraction 回归 |
| R523 / TC523 | 30 条旧冲突修复、跨来源课次、用户编辑、取消、独立 section/ICS、重复同步 | ReconciliationRepairTests、MeetingReconciliationTests、CourseScheduleProjectionTests、native selftest |
| R524 / TC524 | 官方学期/section/校区、教学日与晚课例外、四课实际课次 | OfficialCourseScheduleTests + 真实公开读取 |
| R525 / TC525 | 处理失败与缺失事实分开、已有截止不重复报缺、提纲不逐条提问、缓存恢复 | CurationReviewPolicy、离线审计及 native selftest |
| R526 / TC526 | 隔离真实 Canvas、应用窗口、构建、签名、公开 Release 回读 | 下方验证与发布记录 |

## 真实资料检查

同一组四门课程实际通过 Canvas API 读取课程资料；每轮取得 87 个 sources，另有 4 条接口/资料可见性警告，成功资料与原本缓存均保留。官方源四课生成 **117 次**（18647-A 39、18794-A 26、19688-A 13、18749 39），核对每组星期、开始/结束时刻、学期范围、假期和 ID 唯一性。发布时的最终显示数还会考虑课程公告停课与独立明确课次，并不强制等于 117。

公开源：[CMU Fall 2026 Schedule of Classes](https://enr-apps.as.cmu.edu/assets/SOC/sched_layout_fall.htm)、[2026–27 Pittsburgh class meeting days](https://www.cmu.edu/hub/calendar/docs/2627-pgh-class-meeting-days.xlsx)。协议、缓存与支持边界见 [研究记录](research/course-schedule-0.5.2.md)。

## 限制与未执行项

自动审批拒绝把最多 8 份真实课程正文发送至当前配置的 OpenAI API（api.openai.com，gpt-6.1-sol），理由为需要对具体外发对象的明确授权。已单独请求确认，此步骤没有执行，也没有通过其他路径重试。实际 Canvas、公开课表、纯本地资料恢复和合成模型响应验证继续执行；不能把这些结果描述成真实模型端到端验证。

未公开的任务截止、不同 section、不明确的相对日期与真正的来源矛盾仍需保留问题。官方适配器目前限定 CMU Pittsburgh 常规完整学期；不把其他学期搜索结果当证据。保留明确 Canvas 单次课次；常规官方 lecture 与额外 recitation 的类型不同，即使时间相交也不会强行合并。

应用使用 ad hoc 签名，未做 Apple 公证；实际安装留给用户亲自验证应用内更新。

## 验证记录

- Swift：`./tools/test.sh` 最终 **305 tests / 34 suites** 通过。公开课表实读测试另在允许联网的环境通过，核对四课 117 次及准确时段。
- Web：**30 tests**、lint、TypeScript/Vite release build 通过。未改前端组件样式，复用既有分页、月视图、历史默认隐藏和原生主题同步。
- 真实资料按本次副本精确重算，旧 badge 为 **56**（24 个问题来源、2 个失败、30 个冲突）；截图更早时为 54。修复后 **15 个待补充来源、0 个待处理冲突**，2 个历史处理失败另列；**7 次公告课次**在本地恢复。没有通过删除原文、伪造完成状态或隐藏实际错误制造清零。
- 重复离线运行后，事件、来源、整理记录和课程选择集合逐值不变，0 模型请求。初次验证错误地要求 JSON 字节相同，失败仅由 Swift Set 的序列化顺序引起；修正验证为集合语义比较，未放宽任何事件或缓存字段比较。
- 中英文隔离应用 selftest 各 **97 项**通过，覆盖实际 WKWebView、缓存重载、canonical 修改类型、别名取消与历史操作。中英文、浅深色共 **36 个真实窗口**完成捕获，涵盖三视图、四门课、待补充和编辑器；复核了分组课次、月视图与统一主题。中文预览输出完成标记后未自行退出，确认全部文件后仅终止其精确路径对应的隔离进程，正式应用未受影响。

过程保留了有效失败：日期与旧冲突的红绿回归；新时间范围 helper 把 ISO 日期连字符误当时段，修复后原断言通过；真实相对日期公告将两句归一到一行时，第二句以数字日期开头导致分句遗漏，已添加真实结构的合成回归并修复；最终只读复核发现三层 alias 传递与修改事项类型入口遗漏，已补回归后关闭。公开网络测试在沙箱 DNS 下失败，获准联网后通过；release 的系统 dsymutil 受沙箱限制，获准运行后构建通过。截图工具首次未同步浅色外观，已修正诊断入口后重拍。

验收日志位于本机 `build/verification/0.5.2/`，包括 `swift-final.log`、`public-schedule-tests.log`、`web-tests.log`、`selftest-*-final.log`、`audit-summary.json`、`offline-cache-repeat.log`、`build-final.log`。真实来源缓存不在仓库。Swift 测试宏存在既有 redundant require 警告，ReUI/Vite 仍提示既有源映射/指令/单包体积警告；未据此改变第三方组件。

## 评分与发布

证据评分 **92/100**：需求 23/25、正确性 24/25、测试 17/20、架构 9/10、代码 9/10、文档交付 10/10。扣分来自真实模型调用待明确授权、公开课表适配范围与仍需原始资料确认的任务日期；不据此扩大为通用浏览代理或猜测缺失值。

版本 **0.5.2 / build 9**，源码与 tag `v0.5.2` 对应 `4f8a34e`。最终候选为 `build/releases/0.5.2-final/`，已通过签名、arm64、版本、ZIP 内嵌公钥更新签名、解压应用签名和 DMG 完整性校验。

[GitHub Release](https://github.com/yangbo-s/Syllapace/releases/tag/v0.5.2) 于 2026-11-05 09:03:31 UTC 公开并设为 latest。草稿四个附件的状态、长度与服务器 SHA-256 均匹配最终候选；公开后重新下载四个附件，哈希与本地一致，重验更新签名、ZIP 应用签名、DMG 完整性及只读挂载后的实际可执行文件。固定 latest appcast 与版本附件逐字节一致。证据：`draft-verification.json`、`public-verification.log`、`public-verification.json`。

公开 DMG SHA-256：`1fafe57036b515f4a515e006a6f9a74543adea7fd2752b28ecbf7558bada6088`；ZIP SHA-256：`843202eac91abe68df0b218d813ef342b41470a75082ee881fa6bc2685b3b8da`。

发布前后只读核对本机应用均为 **0.5.1 / build 8**，可执行文件 SHA-256 不变。未执行本机跨版本安装；用户可自行通过应用内“检查更新”验证。任务专用临时目录中的真实资料、凭据副本和预览 archive 已清理；本机忽略目录仅保留验收记录与窗口证据，不上传私人内容。
