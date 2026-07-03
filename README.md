# MeetingCaptions — 本地实时会议翻译字幕

把会议软件（Zoom / Teams / Google Meet 等）的语音，**在本机**实时识别并（按需）翻译成中文，
显示在一个置顶悬浮字幕窗里。全程不联网、零成本、隐私安全。

## 技术栈（全部本地）

- **音频捕获**：macOS 14.4+ Core Audio *Process Taps* —— 复制指定进程的输出音频，
  同时系统照常把声音播给你的耳机（`.unmuted`）。无需虚拟声卡。切换输出设备自动重建。
- **语音识别（两种引擎可选）**：
  - **英文**：[WhisperKit](https://github.com/argmaxinc/WhisperKit) `base.en`（默认）
    或 Apple 原生 `SpeechAnalyzer`（macOS 26，流式、系统共享模型、无需下载）。
  - **中文**：Apple 原生 `SpeechAnalyzer`（Whisper 多语言小模型对中文太弱）。
- **翻译**：Apple `Translation` 框架，本地英→简中（`zh-Hans`），带 6 句上下文窗口整块精修。
  中文会议直接显示识别结果，不翻译。
- **UI**：主控制窗口 + 精简菜单栏图标 + 置顶不抢焦点的 `NSPanel` 悬浮字幕窗。
- **会议纪要**：停止时可导出中英对照 markdown。

## 会议语言 / 引擎选择

主窗口顶部：
- **会议语言**：英文（译中）/ 中文（不翻译）
- **英文识别引擎**（仅英文模式）：Whisper / Apple 原生 —— 可 A/B 对比，
  实测 Apple 在印度英语上分句和标点略优、且省 145MB 模型。

首次用 Apple 引擎会弹「语音识别」授权框，点允许（一次性）。

## 首次运行

1. 构建并拷到稳定位置（TCC 授权绑定签名身份，别每次从 DerivedData 直接跑）：
   ```sh
   ./build.sh
   ```
   会生成 `~/Desktop/MeetingCaptions.app` 并启动。

2. 首次会**下载两个模型**（需要联网一次，之后全离线）：
   - WhisperKit `base.en`（约 145MB，第一次识别时自动下载）
   - Apple 简体中文翻译模型（第一次翻译时系统弹窗询问下载）

3. **授权**：第一次开始捕获时，系统会弹「系统音频录制」授权，点允许。
   （菜单栏图标旁会出现紫色圆点，表示正在录制系统音频——不是麦克风。）

## 使用

1. 点菜单栏的 💬 图标。
2. 先让会议软件**正在播放声音**（有声音的进程才会出现在列表里）。
3. 点「🔄 刷新应用列表」，然后点你要翻译的应用（Zoom / Teams / Chrome…）。
4. 悬浮窗开始显示：**中文（大字）+ 英文原文（小字）**。
5. 拖动悬浮窗背景可移动；「鼠标点击穿透」让你能点到窗口下面的东西。

## 已知限制（MVP）

- **Chrome / Meet / Teams 走 helper 进程**：代码已自动把同一 app 的所有 helper 进程一起 tap，
  但如果没声音请先播放音频再刷新。
- **延迟**：识别按窗口滚动（~每 0.25s 拉一次，Whisper 每次跑一段），
  中文翻译在一句话「定稿」后出现（检测到停顿）。这是准确率与延迟的折中。
- **口音**：`base.en` 对印度口音尚可；若不够准，改 `TranscriptionEngine.load(model:)`
  为 `openai_whisper-small.en`（更准但更慢）。
- **切换输出设备**：如果开着字幕时换耳机/扬声器，需要停止再重新开始
  （聚合设备绑定的是启动时的默认输出）。
- 未做：说话人区分、历史记录导出、自定义术语。

## 文件结构

| 文件 | 职责 |
|---|---|
| `MeetingCaptionsApp.swift` | App 入口、菜单栏、进程选择 |
| `CaptureCoordinator.swift` | 顶层协调：捕获→识别→翻译→字幕 |
| `AudioProcessEnumerator.swift` | 枚举/解析正在出声的会议进程 |
| `ProcessTapCapture.swift` | Core Audio 进程 tap + 私有聚合设备 + 重采样到 16k |
| `FloatRingBuffer.swift` | 实时线程↔消费线程的无锁环形缓冲 |
| `TranscriptionEngine.swift` | WhisperKit 滚动窗口识别 + 停顿定稿 |
| `TranslationBridge.swift` / `TranslationPump.swift` | Apple 翻译框架逐行英→中 |
| `CaptionStore.swift` / `CaptionsView.swift` | 字幕数据模型 + 悬浮窗视图 |
| `OverlayController.swift` | 悬浮 `NSPanel` 生命周期 |

## 重新构建

```sh
xcodegen generate      # 改了 project.yml 后
./build.sh             # 构建 + 拷到桌面 + 启动
```
