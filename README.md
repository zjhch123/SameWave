# 同频（MeetingCaptions）

“同频”是一款面向一对一会议的 macOS 实时字幕应用。它将系统音频视为“对方”、麦克风视为“我”，在本机完成双路语音识别和英译中，并按发言顺序生成可恢复、可导出的会议记录。

## 主要能力

- 通过 ScreenCaptureKit 捕获系统输出，通过 AVFoundation 捕获麦克风。
- 两路音频分别使用 Apple `SpeechAnalyzer` 进行本地流式识别。
- 英文会议使用 Apple Translation 本地翻译为简体中文；中文会议直接显示原文。
- 以 Section 组织双方发言，中文译文为主、英文原文为辅。
- 会议从开始起增量保存到 SwiftData，支持暂停、恢复、崩溃恢复、历史查看和 Markdown 导出。
- 可选配置 OpenAI 兼容服务，生成实时洞察、历史洞察和会后优化稿。

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

3. 本机开发签名配置完成后，可构建、安装并启动固定路径下的应用：

   ```sh
   ./build.sh
   ```

   脚本会停止已运行的桌面版应用，覆盖 `~/Desktop/同频.app` 后重新启动。

4. 首次运行时按系统提示允许语音识别、麦克风和屏幕录制权限，并准备识别与翻译所需的系统语言资源。

## 基本操作

1. 在主窗口中选择“英→中”或“中文”。
2. 按需开启“我的麦克风”，然后开始会议。系统音频会被统一记为“对方”。
3. 会议中可暂停或恢复；结束后记录自动进入左侧历史。
4. 历史记录可导出为 Markdown。配置 AI 服务后，还可生成洞察或优化稿。

## 数据与隐私

音频捕获、语音识别、Apple Translation 和会议历史均在本机处理，应用不保存音频。AI 能力不属于离线主链路：当用户配置并触发服务后，会议文字会发送给所选第三方 OpenAI 兼容接口，音频不会由该链路上传。

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
├── doc/          # 架构、流水线、数据、AI、决策和开发指南
├── AGENTS.md     # 仓库内协作与验证约束
├── project.yml  # XcodeGen 工程声明，是构建配置的事实来源
└── build.sh     # 本机签名、安装与启动脚本
```

`MeetingCaptions.xcodeproj` 由 XcodeGen 生成且不纳入版本控制。源码级架构、状态机、数据模型和验证方式见 [项目文档索引](doc/README.md)。

## 当前边界

- 一对一场景通过双物理通道区分“我/对方”；多个远端参与者不会被进一步分离。
- ScreenCaptureKit 捕获除本应用外的全部系统输出，不提供按会议应用筛选。
- 只支持英文译简体中文与中文直显。
- 当前没有自动化测试 target；核心状态机与持久化改动需要补建测试。
