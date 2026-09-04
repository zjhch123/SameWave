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
