# AGENTS.md — 同频（MeetingCaptions）

## 适用范围

- 本文件约束整个 `MeetingCaptions` 仓库。所有项目源码、文档和工程声明都从仓库根目录使用相对路径，不依赖仓库外的工作区布局。
- 同频是面向 macOS 26+ 的 Swift 6 原生应用：SwiftUI/AppKit 界面、ScreenCaptureKit/AVFoundation 音频、Apple Speech 本地识别、Translation 本地翻译、SwiftData 历史记录，以及可选的 OpenAI-compatible 洞察服务。
- 开始改动前先执行 `git status --short`。工作区可能已有用户改动；不得覆盖、回退或顺手整理与当前任务无关的内容。

## References

- 项目文档目录位于 [`doc/`](doc/)，总索引是 [`doc/README.md`](doc/README.md)。它们是帮助快速建立上下文的 reference，不是兼容性契约；涉及行为判断时，以当前源码、`project.yml` 和明确的需求文档为准。若 reference 与实现冲突，先确认真实行为，再在当前任务范围内同步文档，不要为维持旧文档描述而保留旧路径。
- 按任务读取必要的 reference，不要无差别加载整个目录：

| 任务领域 | 先读 reference | 再核对源码/需求 |
|---|---|---|
| 项目定位、分层、模块职责 | [`01-项目全景与架构.md`](doc/01-项目全景与架构.md) | `project.yml`、相关入口与调用链 |
| 音频、ASR、Section、翻译 | [`02-实时字幕与翻译流水线.md`](doc/02-实时字幕与翻译流水线.md) | [`会议实时翻译-对话渲染需求与状态机.md`](doc/会议实时翻译-对话渲染需求与状态机.md)、`Sources/Meeting/CaptionStore.swift`、`Sources/Meeting/CaptureCoordinator.swift` |
| 开始、暂停、恢复、历史、导出 | [`03-会话生命周期与数据.md`](doc/03-会话生命周期与数据.md) | `Sources/Meeting/CaptureCoordinator.swift`、`Sources/History/MeetingHistory.swift`、`Sources/History/TranscriptExporter.swift` |
| 洞察、服务商、Prompt、会后优化 | [`04-AI洞察与会后优化.md`](doc/04-AI洞察与会后优化.md) | `Sources/Insights/InsightEngine.swift`、`Sources/Insights/InsightModels.swift`、provider/settings 文件 |
| 架构取舍、演进方向、已知边界 | [`05-设计思想、演进与边界.md`](doc/05-设计思想、演进与边界.md) | 当前工作树、需求和可复现证据 |
| 构建、权限、改动入口、验证矩阵 | [`06-开发与验证指南.md`](doc/06-开发与验证指南.md) | `project.yml`、`build.sh`、当前开发环境 |
| 已采纳决策及其原因 | [`DECISIONS.md`](doc/DECISIONS.md) | 对应需求、实现、测试和最新 reference |

## 工程原则

- 不保留向后兼容。需求替换旧路径时删除旧实现、旧开关和死代码，不增加 fallback、双写、适配层或迁移分支。
- 选择满足当前需求的最简单端到端实现。避免推测性的协议、配置、工厂、服务定位器和只有一个实现的抽象。
- 按层增长：先保持一个可构建、可运行的纵向切片，再叠加能力；不以破坏现有工作产品为代价铺设未完成架构。
- 保持职责边界清晰：View 负责渲染，Store 负责状态，Coordinator 负责编排，capture/ASR/provider 负责 I/O 边界，持久化负责落盘。
- 优先使用项目已有能力和 Apple 公共框架。添加依赖前先检查现有框架、依赖文档与类型；成熟库能显著减少复杂度时才引入，并说明理由。
- 做长期可维护的架构决定，不提交注定被替换的临时方案。
- 遵循 Swift API Design Guidelines；优先值类型、明确状态和结构化并发。不要用 `@unchecked Sendable`、`nonisolated(unsafe)` 或关闭检查来掩盖并发问题；现有例外也不得无依据扩散。
- 错误必须在正确边界被保留和呈现。不要使用空 `catch`、无说明的 `try?`、虚假成功状态或吞掉构建退出码。

## 决策记录

- 当任务形成了会长期影响产品行为、架构边界、状态机、数据模型、安全/隐私、外部依赖或工程工作方式的决策时，必须在任务完成前维护 [`doc/DECISIONS.md`](doc/DECISIONS.md)。先做出并验证决定，再记录最终结论；不要把尚未采用的设想写成既定事实。
- 普通实现细节、机械重命名、需求已唯一确定的改动和容易撤销的局部选择不单独记入，避免决策日志退化成 changelog。
- 每项决策使用稳定 ID，说明日期、状态、背景、最终决定、被否决方案、理由/权衡、影响和相关文件。新记录置顶；若旧决策被替代，保留原记录并标为 `Superseded`，链接到替代它的新决策，不通过改写历史制造“从未改变过”的假象。
- `DECISIONS.md` 负责回答“为什么这样决定”；领域 reference 负责描述“当前系统是什么、如何工作”。决定改变当前行为时，两者必须在同一任务中同步，且都要回到源码和测试核验。
- 如果任务没有产生上述级别的新决策，不要为了形式添加空记录；最终说明无需声称更新了决策日志。

## 工作方式

1. 先从 [`doc/README.md`](doc/README.md) 选择与任务相关的 reference，再定位需求对应的用户路径和完整数据流，阅读调用方、实现和下游消费者；不要仅凭 reference、文件名或 README 猜测。
2. 写下需要保持的状态不变量和失败场景，再进行最小、完整的修改。修根因，不在 UI 层遮盖底层错误。
3. 优先让纯逻辑与平台 I/O 解耦，以便确定性测试；不要为测试复制生产逻辑。
4. 改动纯逻辑（尤其 `CaptionStore`、会话生命周期、解析、洞察合并或持久化映射）时必须添加或更新 XCTest。当前仓库尚无测试 target；首次需要单元测试时，在 `project.yml` 建立最小 `MeetingCaptionsTests` target，而不是跳过验证。
5. 修改工程配置后重新运行 XcodeGen，并审查生成的 plist/entitlement 差异。不要提交 `.build`、DerivedData、生成的 xcodeproj 或本地配置。
6. 若一次缺陷暴露了可重复的盲区，把经验固化为测试、脚本、可执行检查或本文件中的短规则；不要只靠更多注释提醒下一位代理。

## 验证门槛

在仓库根目录执行以下无签名验证；这是每次代码或工程配置改动的最低完成条件：
```
xcodegen generate
xcodebuild -project MeetingCaptions.xcodeproj \
  -scheme MeetingCaptions \
  -configuration Debug \
  -derivedDataPath .build \
  CODE_SIGNING_ALLOWED=NO \
  build
```
- 若存在测试 target，再运行相应 `xcodebuild test`；报告实际运行的 scheme/destination 和结果。不得声称测试通过却只做了编译。
- 根据改动补充最小人工 smoke test：启动/权限、系统音频、麦克风、英译中、中文直出、双人抢话、暂停/恢复/结束、崩溃恢复、历史/导出、洞察失败降级。只验证受影响路径，不机械执行无关矩阵。
- `build.sh` 会使用个人签名、终止并覆盖 `~/Desktop/同频.app` 后启动应用。除非任务明确需要签名/TCC 的端到端验证，否则不要运行；绝不能修改或假定其中的个人证书适用于其他环境。
- 无法执行某项验证时，明确说明缺失的环境能力、已经完成的替代检查和剩余风险，不得静默跳过。

## 完成定义

- 当前需求端到端成立，旧路径已删除，没有无关重构。
- Golden invariants 仍成立；新增行为具备可重复验证或清楚的人工验证步骤。
- XcodeGen 生成成功且无签名 Debug 构建通过；相关测试通过。
- 本次若形成了需要长期保留的决策，`doc/DECISIONS.md` 已记录，相关领域 reference 已同步。
- 用户可见行为、权限、配置、核心状态机或架构改变时，同步更新 README、对应的 `doc/` reference、需求文档或本文件中的 reference 路由。
- 最终说明改了什么、验证了什么、仍有哪些风险；不要用代码注释或 TODO 代替未完成工作。
