# 同频（MeetingCaptions）

“同频”是一款面向一对一会议的 macOS 实时字幕应用。它将系统音频视为“对方”、麦克风视为“我”，在本机完成双路语音识别和按所选方向的翻译，并按发言顺序生成可恢复、可导出的会议记录。

## 主要能力

- 通过 ScreenCaptureKit 捕获系统输出，通过 AVFoundation 捕获麦克风。
- 两路音频分别使用 Apple `SpeechAnalyzer` 进行本地流式识别。
- 可在设置的“词表”Tab 编辑并持久化英文产品名、人名和缩写，以提高本地识别命中率。
- 源语言和目标语言都可选择“英语”或“简体中文”；语言不同时使用 Apple Translation 本地翻译，语言相同时直接显示识别结果。
- 以 Section 组织双方发言；翻译时以目标语言为主、源语言为辅，同语言时不重复显示原文。
- 会议从开始起增量保存到 SwiftData，支持暂停、恢复、崩溃恢复、历史查看和 Markdown 导出。
- 可选配置支持 strict JSON Schema Structured Outputs 的 AI 服务；洞察、优化稿和会议标题都使用独立的强类型输出契约。
- 内置通义千问和 Kimi 的 Structured Outputs 模型；自定义 AI 服务可填写域名、带版本路径的地址或完整接口地址，并通过“测试连接”验证嵌套结构化输出契约。
- 录制、暂停和结束由显式状态机管理；结束时先排空音频、ASR 和翻译，再完成最终保存。

## 系统要求

- macOS 26.0 或更高版本。
- Xcode 26+ 与 macOS 26 SDK。
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)。
- 使用 [`build.sh`](build.sh) 安装运行时，需要将脚本中的签名身份改为本机可用的 Apple Development 证书。

## 开始使用

1. 在仓库根目录生成 Xcode 工程：

   ```sh
   xcodegen generate
   ```

2. 进行无签名编译检查：

   ```sh
   xcodebuild -project MeetingCaptions.xcodeproj \
     -scheme MeetingCaptions \
     -configuration Debug \
     -derivedDataPath .build \
     CODE_SIGNING_ALLOWED=NO \
     build
   ```

3. 运行单元测试：

   ```sh
   xcodebuild test -project MeetingCaptions.xcodeproj \
     -scheme MeetingCaptions \
     -configuration Debug \
     -derivedDataPath .build \
     CODE_SIGNING_ALLOWED=NO \
     -destination 'platform=macOS'
   ```

4. 本机开发签名配置完成后，可构建、安装并启动固定路径下的应用：

   ```sh
   ./build.sh
   ```

   脚本会停止已运行的桌面版应用，覆盖 `~/Desktop/同频.app` 后重新启动。

5. 首次运行时按系统提示允许语音识别、麦克风和屏幕录制权限，并准备识别与翻译所需的系统语言资源。

## 基本操作

1. 如需维护英文识别词表，打开设置（⌘,）的“词表”Tab，每行填写一个词或短语并保存。
2. 如需使用 AI，打开“智能洞察”Tab。选择自定义服务时，填写 API 地址、Key 和支持 `json_schema` 的模型 ID，然后用“测试连接”验证完整能力。
3. 在主窗口分别选择源语言和目标语言；两个菜单都提供“英语”和“简体中文”。
4. 按需开启“我的麦克风”，然后开始会议。系统音频会被统一记为“对方”。
5. 会议中可暂停或恢复；结束后记录自动进入左侧历史。
6. 历史记录可导出为 Markdown。配置 AI 服务后，还可生成洞察或优化稿；首次优化时用独立请求生成标题，成功后不再重复生成。

## 数据与隐私

音频捕获、语音识别、Apple Translation 和会议历史均在本机处理，应用不保存音频。AI 能力不属于离线主链路：当用户配置并触发服务后，会议文字会发送给所选第三方 Structured Outputs 接口，音频不会由该链路上传。

如果本地 SwiftData 容器无法打开，应用会明确阻止新会议并显示错误，不会静默改用内存存储制造“已保存”假象。

## 仓库结构

```text
.
├── Sources/
│   ├── App/          # 应用入口、主窗口与 macOS 窗口装配
│   ├── Capture/      # 系统音频、麦克风与 Apple Speech I/O
│   ├── Meeting/      # 实时会话、Section 状态与翻译
│   ├── History/      # SwiftData 历史、详情与导出
│   ├── Insights/     # AI 洞察、服务商、设置与卡片
│   ├── Shared/       # 跨领域共享的小型基础能力
│   └── Resources/    # Asset Catalog、Info.plist 与 entitlements
├── Tests/        # 状态机、翻译调度、持久化与 AI 纯逻辑测试
├── doc/          # 架构、流水线、数据、AI、决策和开发指南
├── AGENTS.md     # 仓库内协作与验证约束
├── project.yml  # XcodeGen 工程声明，是构建配置的事实来源
└── build.sh     # 本机签名、安装与启动脚本
```

`MeetingCaptions.xcodeproj` 由 XcodeGen 生成且不纳入版本控制。源码级架构、状态机、数据模型和验证方式见 [项目文档索引](doc/README.md)。

## 当前边界

- 一对一场景通过双物理通道区分“我/对方”；多个远端参与者不会被进一步分离。
- ScreenCaptureKit 捕获除本应用外的全部系统输出，不提供按会议应用筛选。
- 当前语言范围固定为“英语”和“简体中文”，支持两个翻译方向及两种同语言直显组合。
- 单元测试覆盖可确定执行的领域逻辑；真实音频、权限、Speech 和 Translation 仍需在已签名应用中做人工 smoke test。
