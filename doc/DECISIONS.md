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

## DEC-20260904-001：自定义 AI 地址自动规范化，并把模型发现作为可选辅助

- **日期**：2026-09-04
- **状态**：Accepted
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
- **状态**：Accepted
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
- **状态**：Accepted
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
