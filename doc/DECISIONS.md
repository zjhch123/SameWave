# 同频决策记录

本文件记录已经采纳、会长期影响项目的重要决定，重点回答“为什么这样做”。当前架构和实现细节仍由各领域 reference 与源码描述；本文件不是 changelog、需求池或待办列表。

## 维护规则

- 记录范围：产品行为、架构边界、核心状态机、数据模型、安全/隐私、外部依赖和工程工作方式中的重要选择。
- 记录时机：决定已经完成评估并被采纳后、相关任务结束前。提案和未验证设想不记作 `Accepted`。
- 排序与编号：新决策置顶；ID 使用 `DEC-YYYYMMDD-NNN`，创建后永不复用。
- 状态：使用 `Accepted` 或 `Superseded`。决策被替代时保留原文，标记替代它的新 ID。
- 内容：简要写清背景、决定、否决方案、理由/权衡、影响、验证证据和相关文件。
- 粒度：不记录机械改名、普通 bug 修复、需求已唯一确定的实现步骤或容易撤销的局部细节。
- 一致性：决策改变当前系统时，同步更新相关领域 reference、需求、源码与测试；发生冲突时以当前源码和明确需求为事实依据，并修正文档。

---

## DEC-20260905-001：Markdown 词表逐请求审核、保留成果与选择性保存

- **日期**：2026-09-05
- **状态**：Accepted
- **范围**：Markdown 词表导入、审核、取消/重试、保存与诊断边界
- **替代**：DEC-20260904-016 中停止清空结果的语义，以及 DEC-20260904-014 / 010 / 008 中导入确认后仍须回 Settings 保存的路径。首次选择文件顺序、独立窗口、关闭即取消和原有串行预算继续有效。

### 背景

串行请求需要等待全部完成后才能审核，成功成果在停止时丢失，失败只能重新选择整组文件。纯文本审核难以区分选择和编辑，回 Settings 再保存会牵连其他尚未提交的手动修改。隐藏重试也让用户无法判断时间花在何处。

### 决定与不变量

- 每个成功请求立即追加已去重候选；默认勾选，可编辑、全选/全不选并展开本地来源摘录。稳定 ID、原始提取身份和已见集合保证后续结果不覆盖编辑、不重新勾选或恢复同一候选。
- 停止取消当前与待发请求，保留成功候选；无候选时回到文件选择。失败、中断和未发出的请求可单独重试，成功请求永不重发；同一操作固定 provider 配置，各次重试运行仍采用首次尝试加两次重试。
- 关闭生成窗口取消并丢弃本次未保存状态；已保存词表不受影响。仅观察实际 NSWindow 关闭，不让 View 状态变化、隐藏窗口或关闭 Settings 触发取消。token 隔离迟到结果，重新运行先等待旧任务退出，维持严格串行。
- “添加并保存”只持久化勾选的新词，保存时排除正式词表、手动草稿和候选之间的重复。新增词补入手动草稿，其他待保存增删和文本格式保持不变；取消 Settings 不撤销已保存的导入词。保存期间无需停止生成，反馈留在原窗口。
- 文件名和来源摘录由本地原文生成，不作为新字段发送给 AI；原文中不存在的拼写明确提示核对。正文、候选、来源和耗时记录只在本次窗口内存中保留。
- 每次尝试记录单调时钟耗时、成功/错误/停止，默认折叠。计时覆盖 provider 调用至响应校验，不包含重试间隔；不把合计时间冒充服务端推理时间。未基于猜测调整模型、推理参数或并发。

### 未采用方案与权衡

- **全部完成再审核 / 停止清空**：首个可用结果过晚，取消与失败会浪费已完成工作。
- **并发提速**：用户明确要求串行，且当前尚无服务端延迟分解证据。
- **导入后保存整个 Settings 草稿**：会把用户尚未确认的手动增删一起提交。
- **持久化导入队列和断点恢复**：超出当前独立窗口工作流需求；关闭窗口明确放弃未保存进度。
- 局部成功意味着候选可能不覆盖全部文档，因此保留未完成状态和逐次错误，允许明确重试，不伪装成完整成功。

### 验证与影响

- XcodeGen、无签名 Debug 构建通过；`MeetingCaptions` scheme、`platform=macOS,arch=arm64` 全量 XCTest 81/81 通过。
- 覆盖增量结果、Unicode 分片、失败两次重试后继续、停止/迟到响应、仅重试未完成部分、编辑与勾选保留、来源不发送、选择性持久化及保存时去重。原生 NSWindow 测试验证隐藏保留工作、关闭清理，并保留审核视图截图附件。
- 一次初始测试进程以 code 0 提前退出，随后导入测试单独重跑及全量重跑均通过；未据此推断业务代码或服务延迟根因。未调用真实 AI，真实模型耗时与系统文件选择器交互仍需在安装版中核验。
- 相关文件：`Sources/Capture/VocabularyImportController.swift`、`VocabularyImportWindow.swift`、`SpeechVocabularySettings.swift`、`Sources/Insights/VocabularyGenerator.swift`、对应 XCTest、README 与架构/词表/AI reference。

---

## DEC-20260904-016：生成窗口关闭即取消，停止后保留窗口

- **日期**：2026-09-04
- **状态**：Superseded
- **被替代**：停止清空成果由 [DEC-20260905-001](#dec-20260905-001markdown-词表逐请求审核保留成果与选择性保存) 替代；窗口关闭取消、停止不关窗与界面简化继续有效。
- **范围**：Markdown 词表生成、窗口关闭与显式停止语义
- **替代**：[DEC-20260904-014](#dec-20260904-014markdown-词表生成使用独立窗口和应用级任务状态) 中“关闭生成窗口后任务仍继续、重新打开恢复状态”的行为；设置窗口生命周期独立、首次选择顺序、独立审核和显式保存语义继续有效

### 背景

生成窗口已经承载进度、停止和审核，把它关闭后仍在后台继续调用 AI，会让用户难以判断任务是否还在运行，也可能在没有可见反馈时继续产生延迟和费用。另一方面，窗口内的“停止”是终止当前批次后继续操作的控件，不应强制关闭整个工作窗口。

### 决定

- 用户关闭生成窗口时，立即取消在途请求、使运行 token 失效、清空未确认的审核文本并把 Controller 恢复到空闲状态；重新打开不会恢复已关闭的操作。
- 用户点击窗口内“停止”时执行同样的任务取消和状态清理，但不关闭窗口，界面回到可重新选择文件的初始状态。
- 切换 Settings Tab 或关闭 Settings 仍不影响已经打开的生成窗口，因为任务继续由应用级 Controller 持有。
- 初始页不再展示单文件大小、请求字符数和重试次数三组规则卡片；这些约束继续生效并保留在产品文档和具体错误反馈中。

### 未采用方案

- **关闭生成窗口后继续后台运行**：窗口消失与任务存续的心理模型冲突，且费用继续产生但不可见。
- **点击“停止”后自动关闭窗口**：用户通常是想终止当前资料并马上换一组文件，多一次重新进入设置没有价值。
- **只取消网络任务但保留审核状态**：关闭窗口应结束整次操作，否则重新进入时仍会遇到以为已经放弃的旧候选。

### 理由与权衡

窗口关闭代表结束工作流，窗口内停止代表结束当前运行但继续留在工具中，两个动作各自符合 macOS 用户的直觉。代价是误关窗口会丢弃未确认候选，但不会影响已经确认并加入的应用级词表草稿。

### 影响

- `VocabularyImportWindow` 在消失时调用 Controller 的停止与清理；进度页明确提示关闭窗口会终止生成。
- “停止”按钮只重置 Controller，不调用窗口关闭 API。
- README、词表流水线和 AI reference 必须区分关闭 Settings、关闭生成窗口与点击停止三种行为。

### 验证与相关文件

- XCTest 覆盖停止操作将 Controller 与审核文本恢复为空闲状态；XcodeGen 生成和无签名 Debug 构建通过，macOS arm64 测试 68/68 通过。
- 相关文件：[`Sources/Capture/VocabularyImportWindow.swift`](../Sources/Capture/VocabularyImportWindow.swift)、[`Tests/SpeechVocabularySettingsTests.swift`](../Tests/SpeechVocabularySettingsTests.swift)、[`README.md`](../README.md)、[`02-实时字幕与翻译流水线.md`](02-实时字幕与翻译流水线.md)、[`04-AI洞察与会后优化.md`](04-AI洞察与会后优化.md)。

---

## DEC-20260904-015：Markdown 首次选文件先于生成窗口出现

- **日期**：2026-09-04
- **状态**：Accepted
- **范围**：Markdown 词表生成、首次文件选择与窗口呈现顺序
- **替代**：[DEC-20260904-014](#dec-20260904-014markdown-词表生成使用独立窗口和应用级任务状态) 中“先打开独立窗口、再从窗口选择首批文件”的交互；应用级任务状态、独立进度与审核窗口、关闭设置不取消和显式保存语义继续有效

### 背景

入口先打开一个空的生成窗口，再弹系统文件选择器，会让用户经历一次没有信息价值的窗口切换。用户点击“从 Markdown 生成”时的直接意图是选文件；只有选中内容并真正开始处理后，才需要持续存在的进度与审核界面。

### 决定

- 词表设置页的“从 Markdown 生成”按钮直接呈现系统文件选择器，不预先创建生成窗口。
- 用户选中文件后，应用先把文件选择结果交给应用级 `VocabularyImportController`，随即打开独立窗口展示读取、请求进度、失败披露与审核。首次选择被取消时不启动任务，也不打开第二个窗口。
- 如果已有读取、生成或审核工作流，入口直接恢复独立窗口，不再弹出新的文件选择器，避免覆盖在途状态。
- 独立窗口中的“继续选择文件”与“重新选择文件”仍可在该窗口内发起后续选择；这不改变首次从设置页进入时的两阶段顺序。

### 未采用方案

- **始终先打开空窗口再选文件**：多一次窗口跳转，且取消选择后会留下无用窗口。
- **选中文件后仍停留在设置页显示进度**：重新引入任务与 Settings Scene 生命周期耦合，关闭设置会让工作流缺少稳定承载界面。
- **已有任务时仍弹新选择器**：新选择会取消或覆盖当前操作，容易造成误操作和费用浪费。

### 理由与权衡

把系统文件选择器放在入口动作上，符合“先指定输入、再查看处理”的自然顺序；只有任务真正存在时才创建长期窗口。任务和草稿仍由应用层持有，因此窗口呈现顺序的调整不会削弱关闭设置后继续运行与恢复审核的能力。

### 影响

- `SpeechVocabularySettingsView` 持有首次文件选择器的纯界面状态，选择成功后请求打开生成窗口。
- `VocabularyImportController.handleFileSelection` 明确返回是否应呈现生成窗口；取消选择返回 false，其他成功或错误结果都进入独立窗口状态。
- README、架构、词表流水线和 AI reference 必须区分“设置页直接首次选文件”和“独立窗口承载进度与审核”。

### 验证与相关文件

- XCTest 覆盖取消首次文件选择时不启动工作流、不请求打开第二窗口；XcodeGen 生成和无签名 Debug 构建通过，macOS arm64 测试 67/67 通过。
- 相关文件：[`Sources/Capture/SpeechVocabularySettingsView.swift`](../Sources/Capture/SpeechVocabularySettingsView.swift)、[`Sources/Capture/VocabularyImportWindow.swift`](../Sources/Capture/VocabularyImportWindow.swift)、[`Tests/SpeechVocabularySettingsTests.swift`](../Tests/SpeechVocabularySettingsTests.swift)、[`README.md`](../README.md)、[`01-项目全景与架构.md`](01-项目全景与架构.md)、[`02-实时字幕与翻译流水线.md`](02-实时字幕与翻译流水线.md)、[`04-AI洞察与会后优化.md`](04-AI洞察与会后优化.md)。

---

## DEC-20260904-014：Markdown 词表生成使用独立窗口和应用级任务状态

- **日期**：2026-09-04
- **状态**：Superseded
- **被替代**：首次文件选择与生成窗口的呈现顺序由 [DEC-20260904-015](#dec-20260904-015markdown-首次选文件先于生成窗口出现) 替代；关闭生成窗口后继续运行的语义由 [DEC-20260904-016](#dec-20260904-016生成窗口关闭即取消停止后保留窗口) 替代；应用级任务状态、独立进度与审核窗口、关闭设置不取消和显式保存语义继续有效。
- **范围**：Markdown 词表生成、窗口生命周期、未保存草稿与取消语义
- **替代**：[DEC-20260904-010](#dec-20260904-010ai-生成的新词先在独立窗口审核) 中由设置页持有生成状态、再弹出审核 Sheet 的界面结构；新词去重审核、部分成功和显式保存语义继续有效

### 背景

Markdown 生成原本嵌在词表设置页：说明、选择、进度和结果状态占据较多空间，审核又是设置页上的 Sheet。切换 Tab 或关闭设置会销毁 View 持有的任务与审核状态，使一个可能持续较久的多请求工作流意外依赖配置窗口的生命周期。

### 决定

- 设置页只保留简短用途说明和“从 Markdown 生成”入口。点击后打开独立 SwiftUI `Window` Scene；文件选择、读取、串行请求进度、停止、失败披露、候选编辑和确认都在该窗口内完成。
- `VocabularyImportController` 由应用装配层持有，而不是由 Settings View 创建。切换设置 Tab、关闭设置，甚至暂时关闭生成窗口，都不取消在途任务或清空审核内容；重新打开生成窗口恢复当前状态。只有用户明确点击“停止”或退出应用才终止在途任务。
- `SpeechVocabularyDraft` 同样由应用装配层持有，设置页与生成窗口共享。审核确认只把去重后的新词加入这份应用生命周期内的未保存草稿；关闭设置不会丢失它，但也不会写入正式词表。用户仍须回到词表 Tab 明确点击“保存”才持久化并生效。
- 生成窗口关闭不等同于取消审核。审核页中的“取消，不添加”只放弃本次候选，不修改已有草稿。

### 未采用方案

- **继续把任务放在 Settings View，只把审核改成单独窗口**：关闭设置仍会取消文件读取或生成，不能满足工作流与设置生命周期解耦。
- **生成窗口关闭时自动取消**：用户整理其他窗口或误关窗口会丢失长时间请求的结果，与后台继续、重开查看的目标冲突。
- **审核确认后立即保存正式词表**：会把“确认本批候选”和“应用全部词表更改”混为一个动作，绕过词表现有的显式保存边界。
- **把未保存草稿持久化到磁盘**：当前需求只要求不受设置窗口影响；跨应用重启恢复会引入额外的数据生命周期和冲突语义。

### 理由与权衡

独立 Window 让长任务拥有稳定、清晰的界面边界；应用级 Controller 和草稿则让业务状态不依赖任何窗口是否存在。继续保留最终保存动作，避免 AI 候选在用户尚未确认整份词表时进入 ASR 与洞察链路。代价是关闭窗口后任务仍可能继续产生请求和费用，因此生成中的界面会明确说明这一点，并提供显式“停止”。

### 影响

- `AppDelegate` 统一创建 `SpeechVocabularyDraft` 与 `VocabularyImportController`，并注入设置页和独立生成窗口。
- `SpeechVocabularySettingsView` 不再持有文件导入、生成任务或审核 Sheet；旧 `VocabularyReviewSheet` 删除，审核界面并入独立窗口。
- README、架构、词表流水线和 AI reference 必须说明独立窗口、设置生命周期、关闭窗口继续任务与最终显式保存语义。

### 验证与相关文件

- XCTest 覆盖应用级草稿加入新词后仍不修改正式词表，直到明确保存；XcodeGen 生成和无签名 Debug 构建通过，macOS arm64 测试 66/66 通过。
- 相关文件：[`Sources/App/MeetingCaptionsApp.swift`](../Sources/App/MeetingCaptionsApp.swift)、[`Sources/Capture/VocabularyImportWindow.swift`](../Sources/Capture/VocabularyImportWindow.swift)、[`Sources/Capture/SpeechVocabularySettings.swift`](../Sources/Capture/SpeechVocabularySettings.swift)、[`Sources/Capture/SpeechVocabularySettingsView.swift`](../Sources/Capture/SpeechVocabularySettingsView.swift)、[`Tests/SpeechVocabularySettingsTests.swift`](../Tests/SpeechVocabularySettingsTests.swift)、[`README.md`](../README.md)、[`01-项目全景与架构.md`](01-项目全景与架构.md)、[`02-实时字幕与翻译流水线.md`](02-实时字幕与翻译流水线.md)、[`04-AI洞察与会后优化.md`](04-AI洞察与会后优化.md)。

---

## DEC-20260904-013：Markdown 词表单文件 3 MB、单次选择总计 30 MB

- **日期**：2026-09-04
- **状态**：Accepted
- **范围**：Markdown 词表生成、文件读取与资源边界
- **替代**：[DEC-20260904-009](#dec-20260904-009markdown-词表按-3-mb-读取并串行分批生成)、[DEC-20260904-011](#dec-20260904-011markdown-词表单批按约-100k-英文-tokens-扩大) 和 [DEC-20260904-012](#dec-20260904-012markdown-词表使用-2-万字符请求并容忍单请求失败) 中“多文件合计 3 MB”的读取边界；2 万字符串行请求、重试、部分成功和审核语义继续有效

### 背景

原有 3 MB 上限作用于整次多选，会让多文件能力在实际使用中过于受限。文件已会被拆成有界且串行的 AI 请求，因此需要分开约束“单个文件的本地读取成本”和“一次操作的总资源及请求成本”。

### 决定

- 每个 UTF-8 `.md` / `.markdown` 文件最多 3000000 bytes，一次多选的所有去重文件合计最多 30000000 bytes。两个边界分别向用户显示单文件超限和总选择超限错误。
- 读取前先使用文件资源元数据校验，避免已知超限的文件进入内存；读取后再用实际 `Data.count` 执行同一校验，不依赖元数据永远存在或精确。
- 不增加正文字符总量限制。通过文件边界后的内容继续使用 18000 字符内部片段、20000 字符请求、串行处理、每请求重试 2 次和部分成功语义。

### 未采用方案

- **只把总上限改为 30 MB**：无法防止单个过大文件一次占用大量本地内存，也不符合明确的单文件 3 MB 需求。
- **每个文件 3 MB、不限总量**：用户可以一次选择过多文件，使内存、处理时间、AI 请求数和费用没有单次操作边界。
- **只按字符数限制**：Swift 字符数不能稳定表示 UTF-8 文件体积，无法精确保护本地读取边界。

### 理由与权衡

单文件与总选择两层 byte 边界分别管理局部资源风险和一次操作的最坏成本，同时让多文件功能可以实际处理超过 3 MB 的项目资料。代价是接近 30 MB 的选择会产生大量串行 AI 请求，完成时间和费用会显著增加，但用户可观察进度并主动停止。

### 影响

- `VocabularyDocumentLoader` 使用单文件和总选择两个独立常量与错误；词表设置页明确展示两层上限。
- README、词表流水线和 AI reference 必须同时披露“单文件 3 MB”与“一次选择总计 30 MB”。

### 验证与相关文件

- XCTest 覆盖多文件合计超过 3 MB 可读取、单文件超过 3 MB 拒绝，以及累计 30 MB 边界和超限拒绝；XcodeGen 生成及无签名 Debug 构建通过，macOS arm64 测试 65/65 通过。
- 相关文件：[`Sources/Insights/VocabularyGenerator.swift`](../Sources/Insights/VocabularyGenerator.swift)、[`Sources/Capture/SpeechVocabularySettingsView.swift`](../Sources/Capture/SpeechVocabularySettingsView.swift)、[`Tests/VocabularyGeneratorTests.swift`](../Tests/VocabularyGeneratorTests.swift)、[`README.md`](../README.md)、[`02-实时字幕与翻译流水线.md`](02-实时字幕与翻译流水线.md)、[`04-AI洞察与会后优化.md`](04-AI洞察与会后优化.md)。

---

## DEC-20260904-012：Markdown 词表使用 2 万字符请求并容忍单请求失败

- **日期**：2026-09-04
- **状态**：Superseded
- **被替代**：多文件合计 3 MB 的读取边界由 [DEC-20260904-013](#dec-20260904-013markdown-词表单文件-3-mb单次选择总计-30-mb) 替代；2 万字符请求、串行处理、重试、部分成功、新词审核和显式保存决定继续有效。
- **范围**：Markdown 词表生成、AI 输入预算、重试和部分失败语义
- **替代**：[DEC-20260904-011](#dec-20260904-011markdown-词表单批按约-100k-英文-tokens-扩大) 的 400000 字符请求、500 个候选和 180 秒超时；[DEC-20260904-008](#dec-20260904-008markdown-词表提取生成可审核草稿)、[DEC-20260904-009](#dec-20260904-009markdown-词表按-3-mb-读取并串行分批生成) 和 [DEC-20260904-010](#dec-20260904-010ai-生成的新词先在独立窗口审核) 中“任一批失败则不提交任何结果”的原子成功语义；3 MB 总选择上限、串行处理、新词去重审核和显式保存继续有效

### 背景

400000 字符的单次正文对不同 tokenizer 和 OpenAI-compatible 网关的实际能力偏激进，一旦超时或超过上下文，大块内容需要整体重做。多文件生成本质上是多个独立的候选提取请求；某个请求的网络或 Schema 失败不应丢弃其他已成功的高价值结果，但必须让用户清楚知道审核内容可能不完整。

### 决定

- 一次可选择多个 UTF-8 Markdown 文件，继续使用 3 MB 原始文件总大小上限，不再叠加正文字符总量限制。
- 本地先把段落拆成最多 18000 个 Swift 字符的内部片段，再为片段加上文档定位标记并尽可能组合，使每次 AI 调用的 Markdown 正文不超过 20000 个字符。内部片段只是组装中间单位，不是独立 AI 请求；system prompt、请求说明、Schema 和输出不计入这个 Markdown 正文上限。
- 请求按文档和片段顺序严格串行。每个请求首次失败后最多重试 2 次，即最多调用 provider 3 次；重试前分别等待 500 ms 和 1000 ms。取消操作立即终止，不进入重试或部分成功路径。
- 某个请求在 3 次尝试后仍失败时，记录其序号和错误，继续后续请求。成功请求的候选仍会统一去重、排除当前草稿已有词条，并进入独立审核窗口。审核窗口显示失败请求序号，只有所有请求都失败时才将整次操作报错。
- 每个成功请求恢复最多 50 个候选词和 30 秒 provider 超时。候选仍必须同时满足“具体命名实体”与“语音识别价值”双门槛。

### 未采用方案

- **并发发送多个请求**：会造成突发限流，也使请求顺序、停止和进度语义更难预测。
- **继续使用 400000 字符大请求**：请求数更少，但对 tokenizer、网关和网络稳定性的依赖过大，单次失败的重做成本也更高。
- **任一请求失败就整体失败**：会丢弃其他请求已验证的结果，多文件下失败概率也会随请求数增长。
- **静默忽略失败请求**：审核者会误以为结果覆盖了全部文档，不符合 AI 生成配置数据的透明性要求。

### 理由与权衡

20000 字符正文在不引入 provider 专属 tokenizer 的前提下缩小了上下文和超时风险，串行与有界重试让服务压力和最坏时间可预测。部分成功保留了可用候选，失败披露则防止用户把不完整结果误解为全量分析。代价是接近 3 MB 的资料会产生更多串行请求，处理时间和调用费用也会增加。

### 影响

- `VocabularyGenerator` 返回候选、成功请求数和失败明细；词表页只在全部失败时显示整体错误，部分成功时继续审核。
- README、词表流水线和 AI reference 必须持续区分“实际 AI 请求”和“本地内部片段”，并披露重试、部分成功、费用和第三方数据边界。

### 验证与相关文件

- XCTest 覆盖 20000/18000 字符边界、超长段落无丢失拆分、两次重试、第三次尝试成功、单请求失败后继续、部分结果和进度；XcodeGen 生成及无签名 Debug 构建通过，macOS arm64 测试 63/63 通过。
- 相关文件：[`Sources/Insights/VocabularyGenerator.swift`](../Sources/Insights/VocabularyGenerator.swift)、[`Sources/Capture/SpeechVocabularySettingsView.swift`](../Sources/Capture/SpeechVocabularySettingsView.swift)、[`Sources/Capture/VocabularyReviewSheet.swift`](../Sources/Capture/VocabularyReviewSheet.swift)、[`Sources/Insights/OpenAICompatibleProvider.swift`](../Sources/Insights/OpenAICompatibleProvider.swift)、[`Tests/VocabularyGeneratorTests.swift`](../Tests/VocabularyGeneratorTests.swift)、[`README.md`](../README.md)、[`02-实时字幕与翻译流水线.md`](02-实时字幕与翻译流水线.md)、[`04-AI洞察与会后优化.md`](04-AI洞察与会后优化.md)。

---

## DEC-20260904-011：Markdown 词表单批按约 100k 英文 tokens 扩大

- **日期**：2026-09-04
- **状态**：Superseded
- **被替代**：400000 字符正文、500 个候选、180 秒超时和原子成功语义由 [DEC-20260904-012](#dec-20260904-012markdown-词表使用-2-万字符请求并容忍单请求失败) 替代；3 MB 总选择边界又由 [DEC-20260904-013](#dec-20260904-013markdown-词表单文件-3-mb单次选择总计-30-mb) 替代为单文件 3 MB、单次总计 30 MB；串行处理、进度和审核仍继续有效。
- **范围**：Markdown 词表生成、AI 输入预算、模型能力边界
- **替代**：[DEC-20260904-009](#dec-20260904-009markdown-词表按-3-mb-读取并串行分批生成) 中每批 6000 字符的保守预算；3 MB 总选择上限、串行处理、进度和原子提交决定继续有效

### 背景

6000 字符对英文 Markdown 通常只有约 1500–2000 tokens，会把接近 3 MB 的资料拆成大量请求。当前词表生成面向具备大上下文能力的已配置 AI，用户选择以约 100k tokens 为单批目标来减少请求次数。

### 决定

- 以英文 Markdown 常用粗略比例 4 字符/token 计算，将词表正文单批上限设为 400000 个 Swift 字符，目标约 100k input tokens；内部片段上限设为 390000 字符，为文档标签和分隔符保留空间。
- 单批 strict Schema 候选上限从 50 提高到 500，避免输入扩大后人为丢失长文档中的命名实体；prompt 同时明确上限不是配额，不能为了填满而降低精度。正式 AI 请求超时从 30 秒提高到 180 秒，以覆盖大输入和较长结构化输出，用户仍可主动停止。
- 继续按顺序串行发送批次，并保留 3 MB 多文件总选择上限、批次进度、停止及任一批失败不提交部分结果的语义。
- 该预算不是精确 token 计数，也不代表应用设置模型上下文。所选模型和兼容服务必须自行支持正文、system/user prompt、Schema 与输出之和；中文、代码和不同 tokenizer 可能使 400000 字符显著超过 100k tokens并导致请求失败。

### 未采用方案

- **引入某一服务商的 tokenizer**：当前支持多个内置及自定义 OpenAI-compatible 模型，单一 tokenizer 会给其他模型制造虚假精度并增加依赖。
- **从 `/models` 自动推断上下文**：兼容服务的模型元数据没有统一、可信的上下文字段，应用无法据此可靠调整。
- **固定为 100000 字符**：对英文通常只有约 25k tokens，不能达到用户指定的约 100k-token 目标。

### 理由与权衡

固定 400000 字符是无需引入 provider 分支即可接近英文 100k tokens 的最简单边界，并显著减少大文件请求数量。代价是非英文或代码密集内容的 token 偏差可能很大，较小上下文模型会明确失败；审核和原子提交仍能避免不完整结果进入草稿。

### 影响

- `VocabularyGenerator` 的批次、片段和候选上限扩大，测试使用这些常量构造跨批输入，不再绑定旧的 6000 字符值；`OpenAICompatibleProvider` 的正式完成请求使用 180 秒超时，模型列表发现仍保持短请求边界。
- 词表及 AI reference 必须将 400000 字符描述为英文约 100k tokens 的估算，并提示模型上下文风险；洞察和标题的 6000 字符预算不受影响。

### 验证与相关文件

- XCTest 覆盖 400000 字符预算、跨批进度、超长段落无丢失拆分和后续批次失败时的原子性；XcodeGen 生成及无签名 Debug 构建通过，macOS arm64 测试 62/62 通过。
- 相关文件：[`Sources/Insights/VocabularyGenerator.swift`](../Sources/Insights/VocabularyGenerator.swift)、[`Tests/VocabularyGeneratorTests.swift`](../Tests/VocabularyGeneratorTests.swift)、[`02-实时字幕与翻译流水线.md`](02-实时字幕与翻译流水线.md)、[`04-AI洞察与会后优化.md`](04-AI洞察与会后优化.md)。

---

## DEC-20260904-010：AI 生成的新词先在独立窗口审核

- **日期**：2026-09-04
- **状态**：Superseded
- **被替代**：“所有批次都成功才进入审核”的前提由 [DEC-20260904-012](#dec-20260904-012markdown-词表使用-2-万字符请求并容忍单请求失败) 替代；设置页持有任务并弹出审核 Sheet 的界面结构由 [DEC-20260904-014](#dec-20260904-014markdown-词表生成使用独立窗口和应用级任务状态) 替代；新词去重审核和显式保存决定继续有效。
- **范围**：词表生成、候选词审核、草稿变更边界
- **替代**：[DEC-20260904-008](#dec-20260904-008markdown-词表提取生成可审核草稿) 中“所有批次成功后直接追加到词表编辑草稿”的交互；其余严格 Schema、原子生成、显式保存和数据披露决定继续有效

### 背景

AI 提取结果原本在全部批次成功后直接混入现有词表编辑区。虽然仍需用户保存才会生效，但新旧词条缺少视觉边界，用户很难定位本次生成内容，也无法高效完成逐项审核。

### 决定

- 全部批次成功后，先按词表规范化规则去重，并排除当前编辑草稿中已存在的词条；主编辑区此时不发生变化。
- 若存在新词，弹出独立审核窗口，只展示本次新增候选。用户可以逐行修改或删除，明确点击“添加到词表草稿”后，审核后的内容才与当前草稿合并。
- 取消或关闭审核窗口不添加任何内容。确认合并后仍属于未保存草稿，用户必须再点击词表页的“保存”，才会进入本地识别及后续 AI 使用边界。
- 若没有提取到词条，或提取结果全部已存在，则不打开空审核窗口，只在词表页显示结果状态。

### 未采用方案

- **直接在原词表中高亮新增行**：TextEditor 无法可靠维护逐行来源样式，而且新增内容仍会与用户并行编辑相互影响。
- **生成后立即保存新词**：会绕过用户审核，并改变词表现有的显式保存语义。
- **只显示只读结果列表**：用户仍需回到主编辑区寻找和修正错误词条，不能完成真正的审核。

### 理由与权衡

独立审核窗口给本次生成结果建立清晰边界，且允许在进入主草稿前完成删除和纠错。两阶段确认保留“审核候选”和“保存正式词表”两个不同意图；代价是多一次确认操作，但这是 AI 生成配置数据所需的明确控制。

### 影响

- `SpeechVocabularySettingsView` 在生成完成后只创建审核请求，不再直接修改草稿。
- `VocabularyReviewSheet` 负责候选编辑和确认，`VocabularyCandidateReview` 负责排除当前草稿已有词条。
- README、词表流水线和 AI reference 必须描述独立审核窗口及取消不变更草稿的语义。

### 验证与相关文件

- XCTest 覆盖候选词相对当前草稿的大小写不敏感排重；XcodeGen 生成及无签名 Debug 构建通过，macOS arm64 测试 60/60 通过。
- 相关文件：[`Sources/Capture/SpeechVocabularySettingsView.swift`](../Sources/Capture/SpeechVocabularySettingsView.swift)、[`Sources/Capture/VocabularyReviewSheet.swift`](../Sources/Capture/VocabularyReviewSheet.swift)、[`Sources/Insights/VocabularyGenerator.swift`](../Sources/Insights/VocabularyGenerator.swift)、[`Tests/VocabularyGeneratorTests.swift`](../Tests/VocabularyGeneratorTests.swift)、[`README.md`](../README.md)、[`02-实时字幕与翻译流水线.md`](02-实时字幕与翻译流水线.md)、[`04-AI洞察与会后优化.md`](04-AI洞察与会后优化.md)。

---

## DEC-20260904-009：Markdown 词表按 3 MB 读取并串行分批生成

- **日期**：2026-09-04
- **状态**：Superseded
- **被替代**：每批 6000 字符的保守预算先由 [DEC-20260904-011](#dec-20260904-011markdown-词表单批按约-100k-英文-tokens-扩大) 替代，当前请求预算、重试和原子提交语义由 [DEC-20260904-012](#dec-20260904-012markdown-词表使用-2-万字符请求并容忍单请求失败) 替代，3 MB 总选择边界又由 [DEC-20260904-013](#dec-20260904-013markdown-词表单文件-3-mb单次选择总计-30-mb) 替代为单文件 3 MB、单次总计 30 MB；串行处理和进度决定继续有效。
- **范围**：词表生成、文件读取边界、AI 请求批次、用户进度反馈
- **替代**：[DEC-20260904-008](#dec-20260904-008markdown-词表提取生成可审核草稿) 中的 60000 字符正文上限和 1 MB 读取上限；其余草稿审核、严格 Schema、原子提交和数据披露决定继续有效

### 背景

Markdown 词表生成原先同时设置 60000 字符正文上限和 1 MB 读取上限。既然正文已经按有界批次串行请求 AI，总字符上限不会保护单次模型上下文，反而会拒绝本可安全分批处理的正常文档；1 MB 对多文件项目资料也偏小。长文档处理时间随批次数增加，用户还需要看到明确进度，而不能把串行等待误判为卡住。

### 决定

- 移除 60000 字符正文总量限制。一次多文件选择只按原始文件总大小限制为 3000000 bytes，并继续要求 UTF-8 `.md` / `.markdown` 文件。
- 本地将正文切片并组合为每批最多 6000 字符，按顺序逐批请求当前 `InsightProvider`。该批次预算是应用独立于服务商的输入控制，不代表或配置模型的上下文窗口；实际上下文能力仍由用户选择的模型和服务端决定。
- 读取文件时显示读取状态；生成期间显示已完成批次与总批次数。停止、失败及结果提交语义不变：任一批失败或用户取消时不追加部分结果，全部成功后才把去重候选合并到可审核草稿。

### 未采用方案

- **把文件总量直接提高到某个字符数**：字符数无法稳定表示 UTF-8 文件大小，且仍会形成与分批能力无关的第二套总量边界。
- **依据模型宣称的最大上下文动态放大单批请求**：自定义 OpenAI-compatible 服务的模型元数据与真实限制不可靠，也会让不同服务商具有不一致的成本和失败面。
- **并发发送所有批次**：会造成突发限流，且更难提供可预测的停止和错误语义；词表生成不需要用并发换取交互延迟。
- **去掉所有总量限制**：多文件读取与串行请求仍需要明确的本地资源和成本边界。

### 理由与权衡

3 MB 总文件上限约束本地读取和用户一次操作的最大成本，6000 字符批次则单独约束每次请求；两者职责清晰，也允许超过旧字符上限的资料自然排队处理。串行执行降低限流风险并保持原子提交简单，批次进度补足了长任务的可见性。代价是接近上限的资料可能需要较长时间和较多次 AI 调用，但用户可以观察进度并随时停止。

### 影响

- `VocabularyDocumentLoader` 只校验扩展名、UTF-8 解码和 3 MB 总文件大小，不再汇总或拒绝正文字符数。
- `VocabularyGenerator` 保持 6000 字符单批预算和串行请求，并向设置页报告批次进度。
- README、设置页及词表/AI reference 必须持续说明 3 MB 上限、分批请求、第三方发送和模型上下文边界。

### 验证与相关文件

- XCTest 覆盖超过旧 60000 字符仍可读取、超过 3 MB 拒绝、串行批次进度、分批和原子失败；XcodeGen 生成及无签名 Debug 构建通过，macOS arm64 测试 59/59 通过。
- 相关文件：[`Sources/Insights/VocabularyGenerator.swift`](../Sources/Insights/VocabularyGenerator.swift)、[`Sources/Capture/SpeechVocabularySettingsView.swift`](../Sources/Capture/SpeechVocabularySettingsView.swift)、[`Tests/VocabularyGeneratorTests.swift`](../Tests/VocabularyGeneratorTests.swift)、[`README.md`](../README.md)、[`02-实时字幕与翻译流水线.md`](02-实时字幕与翻译流水线.md)、[`04-AI洞察与会后优化.md`](04-AI洞察与会后优化.md)。

---

## DEC-20260904-008：Markdown 词表提取生成可审核草稿

- **日期**：2026-09-04
- **状态**：Superseded
- **被替代**：60000 字符正文上限和 1 MB 读取上限由 [DEC-20260904-009](#dec-20260904-009markdown-词表按-3-mb-读取并串行分批生成) 替代；生成成功后直接追加草稿的交互由 [DEC-20260904-010](#dec-20260904-010ai-生成的新词先在独立窗口审核) 替代；任一批失败就整体失败的原子生成语义由 [DEC-20260904-012](#dec-20260904-012markdown-词表使用-2-万字符请求并容忍单请求失败) 替代；其余严格 Schema、显式保存和数据披露决定继续有效。
- **范围**：词表生成、AI 数据边界、用户确认语义、批处理失败行为

### 背景

英文识别词表只能逐行手工维护。项目说明、会议议程和团队文档通常已经包含产品名、人名、缩写与专业术语，让用户重复整理既慢又容易遗漏。现有 AI provider 已统一使用 strict JSON Schema，但 Markdown 可能包含敏感信息和提示注入文本，模型提取结果也不能被视为用户已经确认的配置。

### 决定

- 只有 AI 配置完整时，词表页才允许用户明确选择一个或多个 UTF-8 `.md` / `.markdown` 文件生成候选词。一次选择的正文总量最多 60000 字符，并另设 1 MB 读取上限。
- 应用在本地读取正文，不上传文件对象或文件名，也不持久化正文。正文按段落组合为最多 6000 字符的批次，依次发送给当前 `InsightProvider`；每批使用独立 strict Schema 返回最多 50 个、最长 100 字符的单行词条。
- 文档内容被视为不受信任数据。system prompt 要求忽略文档内指令，只提取英语会议中可能口头出现且精确拼写重要的产品、项目、组织、人名、缩写与少见术语，并排除普通词、URL、路径和纯 Markdown/代码语法。
- 所有批次必须全部成功。完成后结果才按现有去空白和大小写不敏感去重规则追加到词表编辑草稿；不覆盖已有草稿、不自动保存。用户仍需检查并点击保存，之后才进入既有的本地 ASR、洞察和优化链路。
- 用户停止、文件无效、内容超限、网络失败或任一批违反 Schema 时，整个操作失败或取消，不把部分结果写入草稿。

### 未采用方案

- **用正则或 Markdown 标记本地猜测关键词**：无法可靠区分普通词、代码标识符和真正会被口头提及的专有词。
- **让 AI 结果直接覆盖或保存词表**：模型可能过度提取或误判，会绕过用户对本地识别偏置及后续第三方发送内容的确认。
- **把所有文档拼成一次无上限请求**：不能覆盖最小上下文模型，且失败成本、费用和截断行为不可控。
- **调用 provider 专属文件上传接口**：会破坏当前单一 OpenAI-compatible Structured Outputs 边界，并增加远端文件生命周期和隐私管理。

### 理由与权衡

复用现有 provider 与严格 Schema，在不新增依赖或第二套 AI 配置的情况下形成完整用户路径。把生成结果停在草稿层，保留了词表原有“显式保存后生效”的不变量；批次原子提交避免用户拿到来源不完整却看似成功的词表。代价是长文档会产生多次串行请求，批次之间无法做全局重要性排序，但本地去重和人工审核足以覆盖当前词表用途。

### 影响

- `VocabularyGenerator` 负责本地文件读取边界、分批、prompt、Schema 校验和结果规范化；词表 View 只负责文件选择、任务状态和草稿合并。
- Markdown 正文成为新的显式第三方数据披露面，README、设置页和 AI reference 必须持续说明。
- 保存后的候选词仍遵循既有生效边界：下一次开始或恢复英文会议时进入 Apple Speech，会后优化读取完整已保存词表，智能洞察只发送当前上下文命中的词条。

### 验证与相关文件

- XCTest 覆盖结构化结果去重、非法多行词条拒绝、后续批次失败时整体失败、超长段落无丢失分批、多文件读取、内容上限和扩展名拒绝；无签名 Debug 构建通过，macOS arm64 测试 58/58 通过。
- 相关文件：[`Sources/Insights/VocabularyGenerator.swift`](../Sources/Insights/VocabularyGenerator.swift)、[`Sources/Capture/SpeechVocabularySettingsView.swift`](../Sources/Capture/SpeechVocabularySettingsView.swift)、[`Sources/Capture/SpeechVocabularySettings.swift`](../Sources/Capture/SpeechVocabularySettings.swift)、[`Sources/Insights/SettingsView.swift`](../Sources/Insights/SettingsView.swift)、[`Tests/VocabularyGeneratorTests.swift`](../Tests/VocabularyGeneratorTests.swift)、[`02-实时字幕与翻译流水线.md`](02-实时字幕与翻译流水线.md)、[`04-AI洞察与会后优化.md`](04-AI洞察与会后优化.md)。

---

## DEC-20260904-007：历史洞察优先使用优化后的原文

- **日期**：2026-09-04
- **状态**：Accepted
- **范围**：历史洞察输入、优化结果回退、实时洞察与标题的事实来源

### 背景

会后优化会保存逐行的 `refinedSource`，修正明显识别错误、专有词拼写和标点，但历史洞察仍固定使用 `sourceText`。这会让用户已经确认并保存的更高质量内容无法改善话题、待办和决定提取。同时，优化采用分批部分成功语义，不能假设每行都存在优化结果。

### 决定

- 用户在历史会议中生成或重新生成洞察时，按时间顺序组装 transcript，每行优先使用非空的 `refinedSource`；该行没有成功优化时单独回退到 `sourceText`。
- 不使用 `refinedTarget` 作为洞察事实来源，避免将译文的二次误差带入结构化洞察。
- 实时洞察没有会后优化结果，继续使用实时 `sourceText`。会议标题继续使用原始 `sourceText`，保持与优化并行生成的时序和结果稳定性。
- 已缓存洞察不因后续优化自动删除或重跑；用户明确点击“重新生成”后，新请求才使用当前优化内容。

### 未采用方案

- **历史洞察始终使用原文**：浪费已保存的识别纠错和专有词改善。
- **使用优化译文**：可能引入翻译偏差，且同语言与跨语言会议的事实来源不再一致。
- **只要有一行缺失优化就整会回退原文**：与分批部分成功设计冲突，会丢失其他成功行的价值。
- **优化完成后自动删除或重生成已有洞察**：会在未经用户确认时删除已保存成果或产生新请求费用。

### 理由与权衡

逐行优先级与现有优化展示的回退语义一致，在不要求全量优化成功的前提下尽可能使用高质量输入。显式保留实时洞察和标题的原文路径，则避免一个共享帮助方法的改动悄然改变其他 AI 用例。代价是旧的缓存洞察不会自动反映后来的优化，但这保留了用户对外部请求和结果替换的显式控制。

### 影响

- `InsightEngine.flatten(lines:preferringRefinedSource:)` 要求每个调用方显式选择文本语义，历史洞察选择优化优先，标题选择原文。
- 洞察词表命中也以最终组装的历史洞察上下文为准，因此优化后恢复的专有词能正确进入洞察 prompt。

### 验证与相关文件

- XCTest 覆盖历史行优先使用 `refinedSource`、空优化逐行回退、时间排序，并锁定标题仍使用原文；无签名 Debug 构建通过，macOS 测试 51/51 通过。
- 相关文件：[`Sources/App/InsightInspector.swift`](../Sources/App/InsightInspector.swift)、[`Sources/Insights/InsightEngine.swift`](../Sources/Insights/InsightEngine.swift)、[`Sources/Insights/MeetingTitleGenerator.swift`](../Sources/Insights/MeetingTitleGenerator.swift)、[`Tests/InsightEngineTests.swift`](../Tests/InsightEngineTests.swift)、[`Tests/MeetingTitleGeneratorTests.swift`](../Tests/MeetingTitleGeneratorTests.swift)、[`04-AI洞察与会后优化.md`](04-AI洞察与会后优化.md)。

---

## DEC-20260904-006：智能洞察仅发送当前上下文命中的用户词条

- **日期**：2026-09-04
- **状态**：Accepted
- **范围**：智能洞察 prompt、词表生效边界、第三方数据披露
- **替代**：[DEC-20260904-005](#dec-20260904-005用户词表同时约束本地英文识别与会后-ai-优化) 中“词表不附加到实时洞察”的决定；会后优化使用完整词表、标题不使用词表及其他决定继续有效

### 背景

智能洞察根据最近对话生成话题、建议、参考回答、待办和决定。对话中出现用户已确认的产品名、人名或缩写时，洞察输出仍可能改坏其拼写。但实时洞察会反复请求，每次附加整份词表会增加不必要的 token 和第三方数据暴露。

### 决定

- `InsightEngine` 读取同一个 `SpeechVocabularySettings`。每个实时或历史洞察请求开始时，在已限制为最近 6000 字符的请求上下文中筛选当前已保存词表，只把实际命中的词条加入 system prompt。
- 匹配使用大小写无关的字面搜索。当词条首尾是字母或数字时，对应端必须是非字母数字边界；搜索会继续检查后续候选，避免前面的子串误命中遮蔽后面的独立词。命中结果保持用户配置顺序和精确拼写。
- prompt 只要求模型在需要提及命中词条时保持精确拼写，明确禁止为了使用词表而植入对话中不存在的信息。空词表或无命中不增加词表段落，洞察 JSON Schema 保持不变。
- 会后优化继续在整次操作内使用完整词表快照；会议标题请求继续不发送词表。

### 未采用方案

- **每次洞察发送整份词表**：实现更直接，但会在滚动请求中反复暴露无关项目名和人名，也占用上下文预算。
- **直接做大小写无关子串匹配**：`PR` 会误命中 `project` 等更长单词。
- **只在客户端替换洞察结果**：无法可靠判断语义对应关系，可能改坏正文，且与现有强类型结构化输出边界冲突。

### 理由与权衡

在已有最近上下文上先做确定性筛选，能让模型得到与当前对话直接相关的拼写提示，同时将每次请求的额外暴露与 token 增量限制在实际使用的词条。代价是子串匹配不会对 ASR 近音误字做模糊召回；这是有意的保守边界，避免将未出现的敏感词条发送给第三方。

### 影响

- 应用装配层把 `SpeechVocabularySettings` 同时注入 `CaptureCoordinator`、`InsightEngine` 和 `TranscriptRefiner`。
- 保存后的词表对下一次智能洞察请求立即生效；已在途请求使用开始时的命中结果，不会在中途变化。
- 命中词条可能包含内部项目名或人名，设置页和领域文档必须持续披露洞察、优化和标题的不同发送范围。

### 验证与相关文件

- XCTest 覆盖大小写无关命中、字母数字边界、后续独立命中、配置顺序、空命中 prompt 和禁止强行植入语义；无签名 Debug 构建通过，macOS 测试 50/50 通过。
- 相关文件：[`Sources/Insights/InsightEngine.swift`](../Sources/Insights/InsightEngine.swift)、[`Sources/App/MeetingCaptionsApp.swift`](../Sources/App/MeetingCaptionsApp.swift)、[`Sources/Capture/SpeechVocabularySettingsView.swift`](../Sources/Capture/SpeechVocabularySettingsView.swift)、[`Sources/Insights/SettingsView.swift`](../Sources/Insights/SettingsView.swift)、[`Tests/InsightEngineTests.swift`](../Tests/InsightEngineTests.swift)、[`01-项目全景与架构.md`](01-项目全景与架构.md)、[`02-实时字幕与翻译流水线.md`](02-实时字幕与翻译流水线.md)、[`04-AI洞察与会后优化.md`](04-AI洞察与会后优化.md)。

---

## DEC-20260904-005：用户词表同时约束本地英文识别与会后 AI 优化

- **日期**：2026-09-04
- **状态**：Superseded
- **被替代**：“词表不附加到实时洞察”由 [DEC-20260904-006](#dec-20260904-006智能洞察仅发送当前上下文命中的用户词条) 替代；会后优化使用完整词表、标题不使用词表及其他决定继续有效。
- **范围**：词表生效边界、会后优化 prompt、隐私披露
- **替代**：[DEC-20260903-003](#dec-20260903-003英文识别词表由用户显式保存并按录制阶段冻结) 中“词表与云端 AI 完全隔离”的决定；其余本地识别、显式保存、阶段快照和模型缓存决定继续有效

### 背景

用户维护的词表包含产品名、人名和缩写，原实现只把它用于 Apple Speech。会后优化第一次运行时没有任何 AI 术语表，模型可能把已经识别正确的专有词改写或错误翻译；后续自动积累的 `glossaryJSON` 也无法表达用户预先确认的准确拼写。

### 决定

- `TranscriptRefiner` 读取同一个 `SpeechVocabularySettings`。每次会后优化开始时冻结当前已保存词表，并把同一份提示传给所有批次；操作进行中修改设置不改变本次运行。
- 用户词表与 AI 上次生成的术语表保持两层：用户词表只表示候选专有词及准确拼写，仅在对话内容匹配时纠正 source，不作为强制字符串替换，也不伪造 target 映射；已有 AI 术语表的翻译映射优先。
- 品牌、产品、人名和缩写没有既定译名时保留原文。空词表明确表示不提供用户专有词提示。
- 词表只随用户明确触发的会后优化发送，不额外附加到实时洞察或标题请求。设置页和隐私文档明确披露该云端边界；Apple Speech 的训练数据和模型文件仍只留在本机。

### 未采用方案

- **把每个用户词条写成 term → 同名 target**：会错误阻止 `Wallet` 等普通术语按上下文翻译。
- **在客户端对优化结果做确定性词条替换**：无法可靠判断语义对应关系，可能改坏正文。
- **只依赖 AI 自动生成的术语表**：第一次优化仍没有用户确认的拼写，而且错误结果可能被继续沿用。
- **把词表发送给所有 AI 请求**：实时洞察和标题不需要逐词校对，会扩大不必要的数据暴露。

### 理由与权衡

复用唯一的已保存词表让识别和会后校对共享用户意图，不增加第二套术语配置。把它作为有条件的 prompt 提示而非翻译映射，既能纠正相近音词和大小写，也避免强制插入无关词。代价是会后优化请求会额外暴露词表内容，因此必须在用户界面和文档中明确说明。

### 影响

- 应用装配层把 `SpeechVocabularySettings` 同时注入 `CaptureCoordinator` 和 `TranscriptRefiner`。
- 保存后的词表对下一次会后优化立即生效；对本地识别仍在下一次开始或恢复会议时生效。
- 词表内容可能包含内部项目名或人名，用户应按所选第三方 AI 服务的数据政策决定是否启用优化。

### 验证与相关文件

- XCTest 覆盖有词表和空词表的 prompt 语义；无签名 Debug 构建验证共享设置接线与 Swift 6 隔离。
- 相关文件：[`Sources/Insights/TranscriptRefiner.swift`](../Sources/Insights/TranscriptRefiner.swift)、[`Sources/App/MeetingCaptionsApp.swift`](../Sources/App/MeetingCaptionsApp.swift)、[`Sources/Capture/SpeechVocabularySettingsView.swift`](../Sources/Capture/SpeechVocabularySettingsView.swift)、[`Sources/Insights/SettingsView.swift`](../Sources/Insights/SettingsView.swift)、[`Tests/TranscriptRefinerTests.swift`](../Tests/TranscriptRefinerTests.swift)、[`02-实时字幕与翻译流水线.md`](02-实时字幕与翻译流水线.md)、[`04-AI洞察与会后优化.md`](04-AI洞察与会后优化.md)。

---

## DEC-20260904-004：AI 结构化输出统一使用 strict JSON Schema

- **日期**：2026-09-04
- **状态**：Accepted
- **范围**：AI provider 契约、模型支持面、解析失败语义、用户配置
- **替代**：[DEC-20260904-001](#dec-20260904-001自定义-ai-地址自动规范化并把模型发现作为可选辅助) 中“任意 OpenAI-compatible 模型可用”的能力判定，以及 [DEC-20260903-002](#dec-20260903-002洞察与会后优化分离实时-ai-只使用有界最新上下文) 中的宽容 JSON 解析边界

### 背景

原 provider 固定发送 `response_format: {"type":"json_object"}`，prompt 再重复完整字段样例。这只能保证合法 JSON，不能保证键、类型和嵌套结构；客户端还会提取 code fence、外围文字并把缺失/错类型洞察字段默认为空值，可能把契约违反显示成虚假成功。OpenAI 官方 Structured Outputs 以及通义千问、Kimi 当前文档都提供 `json_schema` + `strict: true`，但 OpenAI-compatible 这一名称本身不保证该能力。实机验证还发现 Cherry Studio Copilot 网关会接受复杂 Schema 并返回 200，却忽略它并生成错误的顶层数组，原来的简单连接测试因此产生假阳性。

### 决定

- 每个 AI 用例拥有自己的 `LLMResponseSchema`：洞察、异语言优化、同语言优化、会议标题和连接测试分别声明 required 字段、nullable 字段和 `additionalProperties: false`。provider 每次必须在 `response_format` 发送调用方的 Schema 且固定 `strict: true`。
- prompt 保留任务、事实和文风约束，并用一句话同步字段名及语义，但不复制完整 JSON 样例。这样所有 provider 仍走同一条 strict Schema 请求路径，同时降低兼容网关静默忽略 `response_format` 时生成错误顶层结构的概率。assistant content 只允许整体 `JSONDecoder` 解码，不提取 code fence/外围文字或为缺失字段填默认值。
- 检查 `finish_reason` 和拒绝内容；截断、拒绝、400 Schema/参数错误给出独立的用户可读错误，不伪装成通用解析失败。
- 内置服务收缩为已有文档证明 strict Schema 能力的通义千问 `qwen3.8-flash` 和 Kimi `kimi-k3`。删除 DeepSeek、智谱 GLM 及其 JSON Object 路径；自定义模型使用代表真实复杂度的嵌套 Schema 连接测试，确认其端到端可用性。
- 旧服务商 ID 不读取已存 API Key，避免默认改选千问后把另一家的密钥发往阿里端点。用户需要显式重新配置。

### 未采用方案

- **按服务商使用 strict 或 JSON Object**：会使同一产品功能具有两套可靠性语义，且无法对用户承诺固定 Schema。
- **strict 请求失败后自动降级**：会掩盖配置/能力错误并恢复旧宽容路径。
- **仅在客户端校验 JSON Object**：能发现错误，但仍会产生不可用输出和重试成本。
- **引入完整 JSON Schema 依赖**：当前 Schema 简单且服务端负责约束，一个最小可编码 JSON 值类型已足够，新包只会扩大构建和维护面。

### 理由与权衡

结构约束从 prompt 建议升级为 API 契约，原生支持的服务能在 token 生成阶段阻止非法结构，也使 Swift 解码失败具有明确意义。兼容网关可能接受却忽略 Schema，因此字段语义仍需在 prompt 中简述，并由客户端作最后一道严格校验。代价是少量 prompt 重复和自定义网关仍可能偶发失败；收益是无需恢复 JSON Object、宽容解析或 provider 分支，也能覆盖实际使用中的部分兼容入口。

### 影响

- AI 新用例必须在调用 provider 时提供明确 Schema，不能只在 prompt 中描述样例。
- Schema 变更需同时更新 Codable 模型、请求体契约测试和领域 reference。
- 服务商违反 Schema、输出被截断或拒绝时，用户看到对应的真实失败，不会获得空洞察或局部默认值。

### 验证与相关文件

- XCTest 覆盖 strict `response_format` 请求体、内置模型列表、字段语义 prompt、`answer: null`、缺字段/错类型/超量建议和 code fence 拒绝；连接测试使用嵌套对象与数组验证真实 endpoint。Cherry Studio `copilot:gpt-5.5` 实测证明旧 prompt 返回错误顶层数组，加入字段语义后的同一 strict 请求返回可解码对象。
- 相关文件：[`Sources/Insights/LLMProvider.swift`](../Sources/Insights/LLMProvider.swift)、[`Sources/Insights/OpenAICompatibleProvider.swift`](../Sources/Insights/OpenAICompatibleProvider.swift)、[`Sources/Insights/InsightModels.swift`](../Sources/Insights/InsightModels.swift)、[`Sources/Insights/InsightEngine.swift`](../Sources/Insights/InsightEngine.swift)、[`Sources/Insights/TranscriptRefiner.swift`](../Sources/Insights/TranscriptRefiner.swift)、[`Sources/Insights/MeetingTitleGenerator.swift`](../Sources/Insights/MeetingTitleGenerator.swift)、[`Tests/OpenAICompatibleProviderTests.swift`](../Tests/OpenAICompatibleProviderTests.swift)、[`04-AI洞察与会后优化.md`](04-AI洞察与会后优化.md)。

---

## DEC-20260904-003：会议标题成功生成后不随重新优化重复请求

- **日期**：2026-09-04
- **状态**：Accepted
- **范围**：会议标题生命周期、AI 请求成本、历史记录稳定性
- **替代**：[DEC-20260904-002](#dec-20260904-002会后优化并行生成独立持久化的会议标题) 中“重新优化时重新生成标题”的触发规则

### 背景

会议 transcript 在结束后不再变化，已经成功生成的标题也是历史记录的稳定标识。若每次重新优化译文都再次请求标题，会产生没有必要的调用成本，也可能让用户熟悉的列表标题发生漂移。

### 决定

- 只有 `MeetingRecord` 没有非空 `aiTitle` 时，优化操作才并行发起标题请求。
- 标题一旦成功持久化，后续“重新优化”只处理译文，不再请求或覆盖标题。
- 标题请求失败或返回空内容时仍保留时间标题；因为记录仍无有效 `aiTitle`，下一次重新优化会再次尝试生成。
- 当前不增加单独的“重新生成标题”操作。

### 未采用方案

- **每次重新优化都重新生成**：额外消耗一次请求，并会造成历史标题不稳定。
- **标题失败后也永久停止尝试**：一次临时网络或服务错误会让记录永远失去自动标题。
- **增加独立重生成按钮**：当前需求明确要求成功后不再生成，新增控制会扩大不需要的产品状态。

### 理由与权衡

持久化字段本身就是最简单可靠的请求门闩，不需要新增时间戳或生成状态。成功标题保持稳定并节省调用；代价是标题质量不理想时当前没有手动重生成入口。

### 影响

- `MeetingRecord.hasAITitle` 统一判定持久化标题是否有效，并同时驱动请求门闩和显示回退。
- 译文重新优化的批处理、失败语义和持久化保持不变。

### 验证与相关文件

- XCTest 覆盖有效、缺失和空白标题的判定及持久化；无签名 Debug 构建验证条件请求接线。
- 相关文件：[`Sources/History/MeetingHistory.swift`](../Sources/History/MeetingHistory.swift)、[`Sources/App/MeetingStage.swift`](../Sources/App/MeetingStage.swift)、[`Tests/MeetingHistoryStoreTests.swift`](../Tests/MeetingHistoryStoreTests.swift)、[`04-AI洞察与会后优化.md`](04-AI洞察与会后优化.md)。

---

## DEC-20260904-002：会后优化并行生成独立持久化的会议标题

- **日期**：2026-09-04
- **状态**：Superseded
- **被替代**：标题重新生成规则由 [DEC-20260904-003](#dec-20260904-003会议标题成功生成后不随重新优化重复请求) 替代；其余独立请求、持久化与显示决定继续有效。
- **范围**：会后 AI 编排、历史数据模型、会议记录展示

### 背景

历史记录原来只用会议开始时间作为主标题，无法从列表直接识别会议内容。译文优化已经会在用户明确触发时把 transcript 发送给所选 AI 服务，因此同一次操作可以生成内容标题，但标题不应被逐批优化的部分成功状态机绑住。

### 决定

- 用户触发“优化/重新优化”时，同时启动译文优化和标题生成两条独立 Chat Completions 请求。标题直接使用有界的原始 ASR transcript，不等待优化稿。
- 两条请求独立判定成功并分别保存。任一请求失败、取消或返回非法内容，都不回退或丢弃另一条已经成功的结果；重新优化时仅用成功的新标题替换旧标题。
- `MeetingRecord.aiTitle` 保存清洗后的简体中文标题。侧栏和历史详情优先显示有效 AI 标题，把会议开始时间保留为次要信息；没有标题时继续使用开始时间作为确定性主标题。
- 标题任务复用当前 provider 与 JSON 解析边界，但由独立 `MeetingTitleGenerator` 拥有 prompt 和输入预算。切换会议时取消标题与优化任务，并在写入前校验操作 token 和记录 id。

### 未采用方案

- **把标题塞进每批优化响应**：标题会随批次重复、缺少全局视角，并让部分批失败影响标题语义。
- **等待全部优化完成后再生成标题**：增加用户等待时间，也会让优化失败无谓阻止标题生成。
- **标题失败时让整个优化操作失败**：两个增强结果没有一致性依赖，耦合失败只会丢掉可用结果。
- **AI 标题完全替代并隐藏时间**：列表更易识别内容，但会丢失原有的时间定位信息。

### 理由与权衡

独立请求直接符合两个产物不同的输出结构和失败语义，同时可以复用现有 provider 而不扩展 HTTP 层。代价是每次优化会额外产生一次短请求；标题输入采用固定 6000 字符预算，极长且中途多次换题的会议可能更偏向最近话题。

### 影响

- 会后优化按钮现在启动两个可取消任务；按钮进度仍描述逐批译文优化，标题作为并行的轻量增强独立完成。
- SwiftData 会议模型增加可选标题字段，成功生成后立即持久化并驱动现有 SwiftUI 查询更新。
- 会议文字会多发送一次给用户已配置的第三方 AI 服务，但音频仍不上传。

### 验证与相关文件

- XCTest 覆盖标题 JSON 解析、长度边界、输入顺序、provider 调用、持久化和日期回退；无签名 Debug 构建验证 SwiftData 模型与并发任务接线。
- 相关文件：[`Sources/Insights/MeetingTitleGenerator.swift`](../Sources/Insights/MeetingTitleGenerator.swift)、[`Sources/App/MeetingStage.swift`](../Sources/App/MeetingStage.swift)、[`Sources/History/MeetingHistory.swift`](../Sources/History/MeetingHistory.swift)、[`Sources/App/MeetingSidebar.swift`](../Sources/App/MeetingSidebar.swift)、[`Tests/MeetingTitleGeneratorTests.swift`](../Tests/MeetingTitleGeneratorTests.swift)、[`Tests/MeetingHistoryStoreTests.swift`](../Tests/MeetingHistoryStoreTests.swift)、[`03-会话生命周期与数据.md`](03-会话生命周期与数据.md)、[`04-AI洞察与会后优化.md`](04-AI洞察与会后优化.md)。

---

## DEC-20260904-001：自定义 AI 地址自动规范化，并把模型发现作为可选辅助

- **日期**：2026-09-04
- **状态**：Superseded
- **被替代**：自定义模型的能力门槛由 [DEC-20260904-004](#dec-20260904-004ai-结构化输出统一使用-strict-json-schema) 替代；地址规范化和可选模型发现决定继续有效。
- **范围**：AI 服务配置、OpenAI-compatible I/O 边界、设置交互

### 背景

自定义服务原先要求用户同时知道 base URL 的精确格式和模型 ID。不同服务文档有的给域名、有的给 `/v1`，也有的直接给完整 `/chat/completions`；普通用户无法从“URL”标签判断应用会不会再拼接路径。模型 ID 同样经常只能从文档或服务后台查找。

### 决定

- 自定义配置只保留一个“API 地址”输入。它接受裸主机、带路径的 base URL 或完整 Chat Completions 地址，并在界面显示最终请求 URL。裸远程主机补全为 HTTPS `/v1/chat/completions`，localhost 和回环地址补全为 HTTP `/v1/chat/completions`；已有路径只补 `/chat/completions`。
- 从最终 Chat Completions 地址推导同级 `/models`，使用相同 Bearer API Key 获取模型 ID。获取成功后提供选择菜单，但模型 ID 输入始终可编辑。
- 模型发现只减少输入成本，不是配置成立的前提。服务未实现 `/models`、返回空列表或非标准结构时明确提示，并允许用户手动填写模型 ID。
- 删除旧 `customBaseURL` 设置路径，不增加迁移或兼容读取。

### 未采用方案

- **要求用户固定填写带 `/v1` 的 base URL**：把接口拼接规则暴露给非技术用户，也无法适配版本段不是 `/v1` 的网关。
- **只接受完整 `/chat/completions` URL**：结果最明确，但多数服务文档首先展示的是 host 或 base URL，复制成本更高。
- **把 `/models` 作为强制校验**：会错误拒绝能正常补全、但没有标准模型列表接口的兼容服务。
- **为不同网关增加模型发现适配器**：当前标准同级 `/models` 加手动输入已覆盖需求，逐服务分支会扩大维护面。

### 理由与权衡

一套确定性的地址规范化规则让用户无需理解 `/v1` 的含义，同时用“实际请求”消除隐式行为。标准 `/models` 覆盖 Cherry Studio 和常见 OpenAI-compatible 服务，手动输入保留了对非标准实现的可用性。代价是仅提供 host 且服务实际不使用 `/v1` 时仍需粘贴其带版本路径的地址；非标准模型接口也不会被自动探测。

### 影响

- 设置页负责呈现规范化结果和模型发现状态；provider 仍只负责 HTTP I/O。
- 自定义服务是否可保存和测试，以规范化地址、API Key 和模型 ID 是否齐全为准，不依赖模型列表请求成功。
- 后续调整地址推导规则时必须同步 URL resolver 测试，避免 UI 预览与实际请求分叉。

### 验证与相关文件

- XCTest 覆盖裸远程主机、回环地址、已有版本路径、完整端点、模型地址推导、无效地址和模型 ID 解码；无签名 Debug 构建验证设置界面与 provider 集成。
- 相关文件：[`Sources/Insights/OpenAICompatibleProvider.swift`](../Sources/Insights/OpenAICompatibleProvider.swift)、[`Sources/Insights/LLMProvider.swift`](../Sources/Insights/LLMProvider.swift)、[`Sources/Insights/InsightSettings.swift`](../Sources/Insights/InsightSettings.swift)、[`Sources/Insights/SettingsView.swift`](../Sources/Insights/SettingsView.swift)、[`Tests/OpenAIEndpointResolverTests.swift`](../Tests/OpenAIEndpointResolverTests.swift)、[`04-AI洞察与会后优化.md`](04-AI洞察与会后优化.md)。

---

## DEC-20260903-004：独立选择源语言和目标语言，同语言直接旁路翻译

- **日期**：2026-09-03
- **状态**：Accepted
- **范围**：语言选择、实时识别与翻译、历史数据、会后优化

### 背景

原语言模式把“英文译中”和“中文直显”绑定成两个预设，界面一侧像可选项、另一侧像静态结果，无法表达中文译英或英语直显。识别 locale、Translation session、历史恢复和会后优化也都依赖这个单一模式，不能只改控件文案。

### 决定

- 源语言和目标语言分别使用一个可点击菜单，两个菜单都只提供固定名称“英语”和“简体中文”。会话开始后同时锁定，避免运行中改变识别和翻译方向。
- 语言对包含四种组合。源语言决定双路 ASR locale；源语言与目标语言不同时按所选方向创建 Apple Translation session，相同时不创建 session 或翻译请求，直接把识别结果作为目标文字。
- `MeetingRecord.language` 保存完整语言对，恢复、字幕、导出和会后优化都从同一语言对派生行为。四种组合使用互不重复的持久化值，不增加兼容解析、迁移分支或 fallback。

### 未采用方案

- **继续保留“英译中 / 中文直显”预设**：无法满足两个方向独立选择，也继续让目标语言看起来不可操作。
- **同语言仍调用 Translation**：没有语义收益，会增加资源准备、延迟和失败面。
- **只在 UI 层交换标签**：识别 locale、持久化恢复和 AI 优化仍会使用错误方向。

### 理由与权衡

一个固定语言枚举加一个完整语言对，是覆盖当前四种行为的最小领域模型。翻译是否需要可由 `source != target` 唯一推导，避免额外开关产生矛盾状态。代价是当前只支持两种语言；增加新语言时必须同时验证 Speech 与 Translation 的平台能力。

### 影响

- 英文识别词表仅在源语言为英语时进入识别器。
- 不同语言的字幕和导出保留目标主文与源文；同语言不显示重复 source echo。
- 会后优化在不同语言时按保存方向重译，在同语言时只校对原文。

### 验证与相关文件

- XCTest 覆盖固定语言名称、四种组合、同语言旁路、持久化值和优化 prompt；已签名应用用于核对两个语言菜单的可点击视觉。
- 相关文件：[`Sources/Meeting/MeetingModels.swift`](../Sources/Meeting/MeetingModels.swift)、[`Sources/Meeting/CaptureCoordinator.swift`](../Sources/Meeting/CaptureCoordinator.swift)、[`Sources/Meeting/TranslationPump.swift`](../Sources/Meeting/TranslationPump.swift)、[`Sources/App/MeetingStage.swift`](../Sources/App/MeetingStage.swift)、[`Sources/History/MeetingHistory.swift`](../Sources/History/MeetingHistory.swift)、[`Sources/Insights/TranscriptRefiner.swift`](../Sources/Insights/TranscriptRefiner.swift)、[`Tests/MeetingLanguageTests.swift`](../Tests/MeetingLanguageTests.swift)、[`02-实时字幕与翻译流水线.md`](02-实时字幕与翻译流水线.md)。

---

## DEC-20260903-003：英文识别词表由用户显式保存并按录制阶段冻结

- **日期**：2026-09-03
- **状态**：Superseded
- **被替代**：词表与云端 AI 的隔离边界由 [DEC-20260904-005](#dec-20260904-005用户词表同时约束本地英文识别与会后-ai-优化) 替代；其余本地识别、显式保存、阶段快照和缓存决定继续有效。
- **范围**：本地语音识别、设置持久化、双路会话一致性

### 背景

英文识别原先使用源码中固定的 41 个产品名、缩写和人名。实际会议术语会变化，继续依赖发版修改无法让用户及时维护词表；如果运行中的两路识别器直接观察可变设置，又可能在同一阶段使用不同版本。

### 决定

- 设置窗口增加独立“词表”Tab，以每行一个词或短语的形式编辑；只有点击保存才写入 UserDefaults。
- 首次运行保留原 41 个默认词条。保存时去空行、去首尾空白并按大小写不敏感去重；空词表是有效配置。
- 开始或恢复会议时冻结词表快照，系统音频和麦克风使用同一份快照。运行中保存的改动到下一次开始或恢复英文会议时生效。
- 同一词表同时传给 `AnalysisContext.contextualStrings` 和本地 `SFCustomLanguageModelData`。不添加自定义读音、权重或识别结果字符串替换；模型缓存按 locale 与词表内容指纹隔离。

### 未采用方案

- **编辑时立即更新运行中的识别器**：需要重建双路 Speech 生命周期，并会造成当前段落识别上下文突变。
- **仅使用 `contextualStrings`**：会放弃已经验证过的自定义语言模型提示路径。
- **对最终文本做词表纠错**：属于确定性字符串改写，不是用户要求的模型侧偏置，且容易误改语义。

### 理由与权衡

显式保存与阶段快照使配置行为可预期，也保证两路音频的一致性。内容指纹允许复用相同模型，同时确保更新后的词表不命中旧缓存。代价是保存后不会在正在录制的阶段立即生效，首次使用新词表时仍需要等待本地模型准备。

### 影响

- 词表配置和 Apple 自定义模型完全留在本机，与可选云端洞察设置隔离。
- 英文识别器在词表为空时跳过自定义模型；中文识别行为不变。
- 后续修改词表格式、生效时机或模型提示策略时，必须同时检查双路快照和缓存身份。

### 验证与相关文件

- XCTest 覆盖默认值、规范化和空词表持久化；无签名 Debug 构建验证 Speech API 与 Swift 6 并发边界。
- 相关文件：[`Sources/Capture/SpeechVocabularySettings.swift`](../Sources/Capture/SpeechVocabularySettings.swift)、[`Sources/Capture/SpeechVocabularySettingsView.swift`](../Sources/Capture/SpeechVocabularySettingsView.swift)、[`Sources/Capture/NativeSpeechEngine.swift`](../Sources/Capture/NativeSpeechEngine.swift)、[`Sources/Capture/CustomSpeechLanguageModel.swift`](../Sources/Capture/CustomSpeechLanguageModel.swift)、[`Sources/Meeting/CaptureCoordinator.swift`](../Sources/Meeting/CaptureCoordinator.swift)、[`Tests/SpeechVocabularySettingsTests.swift`](../Tests/SpeechVocabularySettingsTests.swift)、[`02-实时字幕与翻译流水线.md`](02-实时字幕与翻译流水线.md)。

---

## DEC-20260903-002：洞察与会后优化分离，实时 AI 只使用有界最新上下文

- **日期**：2026-09-03
- **状态**：Superseded
- **被替代**：共享 JSON 解析边界由 [DEC-20260904-004](#dec-20260904-004ai-结构化输出统一使用-strict-json-schema) 替代；洞察/优化职责分离和实时上下文预算决定继续有效。
- **范围**：AI 责任边界、输入预算、实时会话隔离

### 背景

实时洞察是低延迟、最新快照导向的单飞任务；会后优化是以行为单位、允许部分成功的串行分批任务。旧实现把两者放在一个引擎中，状态和辅助逻辑相互污染。同时，实时洞察传送完整会议，长会议会超过内置最小 8K 模型的上下文。

### 决定

- `InsightEngine` 只负责实时和历史结构化洞察；`TranscriptRefiner` 独立负责会后分批校对、重译和术语表。
- 实时与历史洞察只发送最新、优先保持完整行的 6000 字符。这是 provider-无关的保守预算，不引入每模型 tokenizer 和配置层。
- 实时请求绑定会话 token；重置时取消已知任务并拒绝迟到结果。两个引擎共用 provider 配置和宽容 JSON 解析器，但不共享业务状态。

### 未采用方案

- **保留全能 `InsightEngine`**：两种完全不同的执行/失败模型会继续扩大一个类。
- **永远传送全文**：在已知 8K 模型下不可靠，也会让延迟和成本随会议时长无界增长。
- **增加可配置 tokenizer/预算系统**：当前 provider 和模型种类不足以证明这个复杂度。

### 理由与权衡

责任拆分让每个引擎只拥有一个状态机。最新窗口适合“当下该怎么推进”的实时产品语义，并能适配最小内置模型。代价是长会议的很早内容不再自动出现于洞察上下文，且字符上限只是 token 的近似。

### 影响

- 后续洞察 schema/触发修改进入 `InsightEngine`，逐行优化修改进入 `TranscriptRefiner`。
- AI 结果仍是 additive，不覆盖原始 ASR 事实。
- 如果未来产品需要“全场会议总结”，应设计独立的分层摘要用例，不取消实时上下文上限。

### 验证与相关文件

- XCTest 验证优先保留最新完整行、单行超限后缀和 fenced JSON 解析。
- 相关文件：[`Sources/Insights/InsightEngine.swift`](../Sources/Insights/InsightEngine.swift)、[`Sources/Insights/TranscriptRefiner.swift`](../Sources/Insights/TranscriptRefiner.swift)、[`Sources/App/InsightInspector.swift`](../Sources/App/InsightInspector.swift)、[`04-AI洞察与会后优化.md`](04-AI洞察与会后优化.md)、[`Tests/InsightEngineTests.swift`](../Tests/InsightEngineTests.swift)。

---

## DEC-20260903-001：显式建模会话生命周期，并以可等待 I/O 边界收尾

- **日期**：2026-09-03
- **状态**：Accepted
- **范围**：会话状态机、音频/ASR/翻译并发、持久化可靠性、工程验证

### 背景

旧实现用多个布尔和时间字段拼装会话状态，采集/识别类依赖 unsafe Sendable，结束后固定等待 900ms 就保存。这些边界无法证明最后音频、ASR final 和权威翻译已经完成，旧任务也可能在新会议中迟到回写。SwiftData 错误被吞掉，容器失败时静默改用内存，界面仍可显示“已保存”。工程没有测试 target，且只开启最小并发检查。

### 决定

- 使用 `idle/starting/recording/pausing/paused/stopping` 的单一显式会话状态，UI 布尔从该状态派生。
- `NativeSpeechEngine` 作为 actor 拥有有界音频流、converter 和 Speech 对象。停止时依次排空已接收音频、finalize Speech，并等待主 actor 写入 store。
- `TranslationBridge` 跟踪 pending 和 in-flight；暂停/结束等待 idle，但为不可控的系统 Translation 服务设置 5 秒上限。ASR 和翻译请求携带会话 UUID，迟到结果被丢弃。
- 持久化 API 抛出错误，会议最终内容和 ended 状态在同一次 save 提交，save 失败时 rollback context。启动容器失败时阻止会议，不保留内存 fallback；暂停或最终保存失败时保留挂载会话以便重试。
- 主/测试 target 使用 `SWIFT_STRICT_CONCURRENCY=complete`，建立 XCTest target 固定可确定运行的领域不变量。

### 未采用方案

- **在布尔状态上增加更多 guard**：无法从类型上表达转换中状态，仍会留下矛盾组合。
- **延长固定 sleep**：无论 900ms 还是更长都无法证明 I/O 完成，且平白增加正常路径延迟。
- **容器失败时继续用内存运行**：会让用户对会议已持久化产生错误认知。
- **降低严格并发级别或添加 unsafe 标注**：只会隐藏跨执行器访问，不能建立可证明的所有权。

### 理由与权衡

显式状态和可等待边界使启动、暂停、恢复和结束对应可审查的转换。actor 隔离和完整并发检查把约定变为编译器可验证的规则。主动接受的权衡是：Translation 超过 5 秒时优先保存原文并结束会议，不无限阻塞用户。

### 影响

- `CaptionStore` 只拥有 transcript 领域状态，会话生命周期留在 `CaptureCoordinator`。
- 系统音频是必需链路，初始麦克风失败可降级为仅系统音频；两种失败都显示明确状态。
- 翻译失败是 Section 的显式 `.failed` 状态，原文始终保留。
- 后续对 Section、调度或持久化纯逻辑的修改必须更新并运行测试。

### 验证与相关文件

- XcodeGen 重新生成工程；无签名 Debug 构建和 macOS XCTest 作为最低门槛。
- 相关文件：[`Sources/Meeting/MeetingModels.swift`](../Sources/Meeting/MeetingModels.swift)、[`Sources/Meeting/CaptureCoordinator.swift`](../Sources/Meeting/CaptureCoordinator.swift)、[`Sources/Capture/NativeSpeechEngine.swift`](../Sources/Capture/NativeSpeechEngine.swift)、[`Sources/Meeting/TranslationBridge.swift`](../Sources/Meeting/TranslationBridge.swift)、[`Sources/History/MeetingHistory.swift`](../Sources/History/MeetingHistory.swift)、[`project.yml`](../project.yml)、[`02-实时字幕与翻译流水线.md`](02-实时字幕与翻译流水线.md)、[`03-会话生命周期与数据.md`](03-会话生命周期与数据.md)、[`Tests/`](../Tests/)。

---

## DEC-20260902-002：源码按领域责任组织

- **日期**：2026-09-02
- **状态**：Accepted
- **范围**：源码目录、模块边界、工程导航

### 背景

`Sources/` 中的应用装配、采集、实时会议、历史和 AI 文件全部平铺在同一层。文件数量增长后，仅从名称难以快速判断它的所属用户路径、I/O 边界和主要下游。

### 决定

`Sources/` 固定使用七个一级责任目录：`App`、`Capture`、`Meeting`、`History`、`Insights`、`Shared` 和 `Resources`。业务文件按所属领域放置，而不按 View、Model、Service 等技术类型横向分类。XcodeGen 仍递归纳入整个 `Sources/`，不为每个目录增加独立 target 或抽象层。

### 未采用方案

- **继续平铺**：当前已经难以导航，后续新能力会继续扩大单目录。
- **按 View/Model/Service 分组**：会把同一用户路径拆散到多个目录，弱化领域内聚。
- **立即拆成多 target 或 Swift Package**：当前没有需要编译期隔离的证据，会引入过早的 access control 和构建复杂度。

### 理由与权衡

按领域分组能直接表达职责与变更范围，同时保持单 target 和零额外运行开销。目录边界只是组织约束，尚不提供编译期强制；如果后续出现独立复用、独立测试或显著构建收益，再评估拆 target。

### 影响

- `project.yml` 继续以 `Sources/` 为唯一源码根，Info.plist 和 entitlements 分别从 `Sources/Resources/Info.plist` 与 `Sources/Resources/MeetingCaptions.entitlements` 读取。
- `build.sh`、项目 README、reference 路由和源码链接使用新的领域路径。
- 新文件优先进入现有领域；只有形成新的稳定职责边界时才新增一级目录。

### 验证与相关文件

- XcodeGen 工程重新生成成功，无签名 Debug 构建成功。
- 相关文件：[`project.yml`](../project.yml)、[`README.md`](../README.md)、[`01-项目全景与架构.md`](01-项目全景与架构.md)、[`06-开发与验证指南.md`](06-开发与验证指南.md)。

---

## DEC-20260902-001：建立集中式项目决策日志

- **日期**：2026-09-02
- **状态**：Accepted
- **范围**：工程工作方式、项目文档

### 背景

`doc/` 已经能够说明系统当前的架构与实现，但缺少一个稳定位置记录重要选择的背景、被否决方案和长期影响。只更新“当前如何工作”会丢失“为什么这样决定”，后续容易重复讨论或在不了解约束的情况下推翻已有取舍。

### 决定

使用本文件作为项目唯一的轻量决策日志。凡任务形成会长期影响产品行为、架构、状态机、数据、安全、依赖或工程方式的决定，均在完成前写入；领域 reference 同步维护当前状态。

### 未采用方案

- **只在源码注释中记录**：信息分散，跨模块决策难以发现，也无法清楚保留被替代关系。
- **每个决定建立单独 ADR 文件**：当前项目规模下目录和模板成本偏高，不符合轻量维护目标。
- **把决定混入领域文档**：适合描述当前结论，但难以保留时间、替代方案和演进历史。

### 理由与权衡

单文件日志易检索、维护成本低，并能与按领域拆分的 reference 形成互补。代价是文件会随时间增长，因此通过新记录置顶、稳定 ID 和只记录重要决定控制规模。

### 影响

- 仓库根目录的 `AGENTS.md` 增加决策记录触发条件和完成标准。
- `doc/README.md` 将本文件纳入持续维护入口。
- 后续重要决定必须同步“为什么”的日志与“当前是什么”的领域文档。

### 验证与相关文件

- 已确认 `AGENTS.md` 和 `doc/README.md` 均可通过相对链接访问本文件。
- 相关文件：[`AGENTS.md`](../AGENTS.md)、[`doc/README.md`](README.md)、[`doc/DECISIONS.md`](DECISIONS.md)。

---

## 新决策模板

复制本节并放到最近一条决策之前；删除不适用的提示文字。

```markdown
## DEC-YYYYMMDD-NNN：简短、明确的决定标题

- **日期**：YYYY-MM-DD
- **状态**：Accepted
- **范围**：受影响的产品或技术领域

### 背景

触发决定的问题、约束和已确认事实。

### 决定

最终采用什么；边界是什么。

### 未采用方案

- **方案 A**：不采用的原因。

### 理由与权衡

为什么当前决定最合适，以及主动接受的代价。

### 影响

对产品、代码、数据、运维、安全和后续工作的影响。

### 验证与相关文件

支持该决定的测试、实验、指标、需求和源码位置。
```
