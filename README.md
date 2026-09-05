# SameWave

SameWave is a native macOS live-captioning app for one-on-one meetings. It treats system audio as the other participant and the microphone as you, recognizes both streams locally, translates in the selected direction, and builds a recoverable, exportable transcript in speaking order.

The app, executable, Swift module, project, target, and scheme all use the name **SameWave**. The interface, documentation, export templates, AI insights, and generated titles are in English. Meeting text follows the selected source and target languages.

## Features

- Capture system output with ScreenCaptureKit and microphone input with AVFoundation.
- Recognize both audio streams locally with Apple `SpeechAnalyzer`.
- Edit and save English product names, personal names, and acronyms in the Vocabulary settings tab. With AI configured, generate vocabulary for review from one or more Markdown files to improve recognition and preserve terminology in refinement and insights.
- Select English or Simplified Chinese independently for source and target. Use local Apple Translation when they differ; display recognition directly when they match.
- Organize turns into Sections. Translated captions emphasize the target text with the source beneath it; same-language captions avoid duplicate text.
- Save incrementally to SwiftData from the start of a meeting, with pause, resume, crash recovery, history, and Markdown export.
- Reopen the last selected meeting. Unfinished meetings resume in a paused state. Show a new meeting if the previous selection was a new meeting, is missing, or was deleted.
- Configure AI once in the AI Services settings tab. Insights, refinement, meeting titles, and Markdown vocabulary generation share that configuration, each with its own typed output contract.
- Use built-in Qwen and Kimi models that support Structured Outputs. Custom services accept a domain, a versioned URL, or a complete endpoint; Test Connection verifies a nested structured-output contract.
- Manage recording, pausing, and ending through an explicit state machine. Drain audio, ASR, and translation before the final save.

## Requirements

- macOS 26.0 or later.
- Xcode 26+ with the macOS 26 SDK.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen).
- To install with [`build.sh`](build.sh), use an Apple Development certificate available on your machine in the script's signing configuration.

## Getting started

1. Generate the Xcode project from the repository root:

   ```sh
   xcodegen generate
   ```

2. Build without signing:

   ```sh
   xcodebuild -project SameWave.xcodeproj \
     -scheme SameWave \
     -configuration Debug \
     -derivedDataPath .build \
     CODE_SIGNING_ALLOWED=NO \
     build
   ```

3. Run unit tests:

   ```sh
   xcodebuild test -project SameWave.xcodeproj \
     -scheme SameWave \
     -configuration Debug \
     -derivedDataPath .build \
     CODE_SIGNING_ALLOWED=NO \
     -destination 'platform=macOS'
   ```

4. With local development signing configured, build, install, and launch:

   ```sh
   ./build.sh
   ```

   The script stops the desktop app, replaces `~/Desktop/SameWave.app`, and relaunches it.

5. On first launch, grant speech recognition, microphone, and screen recording permissions when prompted, and prepare the system language resources required for recognition and translation.

## Basic workflow

1. To maintain English recognition and AI terminology, open Settings (⌘,) → Vocabulary, enter one word or phrase per line, and save. After configuring AI, Generate from Markdown opens a file picker, then a separate window for progress and review. Switching or closing Settings does not interrupt generation; closing the generation window cancels it. Each UTF-8 Markdown file can be up to 3 MB, with a 30 MB total selection limit. Documents are processed serially in AI requests of at most 20,000 characters. Each request retries at most twice; a final failure does not block later requests. Successful requests immediately show deduplicated terms for selection, editing, and source inspection. Add and Save persists selected terms. Stop keeps existing results; incomplete requests can be retried. Import saves do not submit other manual settings edits.
2. To use AI, open Settings → AI Services, select a provider, enter an API key, and save. Custom services also require an API URL and a model ID that supports Structured Outputs; Test Connection can verify them first. All four AI features use the saved configuration, and their Configure AI Services actions open this tab directly. Local captions, live translation, manual vocabulary, history, and export remain available without AI.
3. Select source and target languages in the main window. Both menus offer English and Simplified Chinese.
4. Enable your microphone if needed, then start the meeting. All system audio belongs to the other participant.
5. Pause or resume during the meeting. Ended meetings appear in the history sidebar automatically.
6. Export history as Markdown. With AI configured, generate insights or a refined transcript. The first refinement also requests a title independently; a successfully generated title is not requested again.

## Data and privacy

Audio capture, speech recognition, Apple Translation, and meeting history are handled locally. The app does not save audio. AI features are separate from the offline captioning pipeline: configured services receive meeting text when invoked. Markdown vocabulary generation sends selected file contents in batches, without filenames or uploading the original files. Content, source excerpts, and unsaved candidates stay in the window's in-memory session. Refinement also sends the full saved vocabulary; insights send only terms matched in recent context; titles send no vocabulary. The AI pipeline never uploads audio.

If the local SwiftData container cannot open, the app blocks new meetings and displays an error. It does not silently switch to memory storage and imply that data was saved.

The bundle ID is `com.plus.samewave`, shared by the UserDefaults and Keychain namespaces. Speech models are cached under `Application Support/SameWave/SpeechLanguageModel`. Settings, vocabulary, keys, and model caches from an older app identity are not read or migrated; moving from that identity requires reconfiguration and may require permissions again. Existing data files are not deleted, and the SwiftData history model and storage implementation are unchanged. The English display-name change retains the current bundle ID and storage namespaces.

## Repository layout

```text
.
├── Sources/
│   ├── App/          # App entry, main window, settings navigation, macOS integration
│   ├── AI/           # Shared AI configuration, providers, requests, response parsing
│   ├── Capture/      # System audio, microphone, and Apple Speech I/O
│   ├── Meeting/      # Live sessions, Section state, and translation
│   ├── History/      # SwiftData history, details, and export
│   ├── Insights/     # Insights, refinement, titles, and vocabulary generation
│   ├── Shared/       # Small utilities shared across domains
│   └── Resources/    # Asset Catalog, Info.plist, and entitlements
├── Tests/            # State machines, translation scheduling, persistence, AI logic
├── doc/              # Architecture, pipelines, data, AI, decisions, development
├── AGENTS.md         # Collaboration and validation rules
├── project.yml       # XcodeGen declaration; build configuration source of truth
└── build.sh          # Local signing, installation, and launch
```

`SameWave.xcodeproj` is generated by XcodeGen and excluded from version control. See the [documentation index](doc/README.md) for architecture, state machines, data models, and validation.

## Current boundaries

- Two physical channels distinguish you from the other participant in one-on-one meetings; multiple remote participants are not separated.
- ScreenCaptureKit captures all system output except this app, without a meeting-app selector.
- The language set is English and Simplified Chinese, supporting both translation directions and both same-language combinations.
- Unit tests cover deterministic domain logic. Real audio, permissions, Speech, and Translation still require manual smoke tests in the signed app.
