# SameWave

SameWave is a native macOS meeting workspace for preparation, live captions, and review. It treats system audio as the other participant and the microphone as you, recognizes both streams locally, translates in the selected direction, and builds a recoverable, exportable transcript in speaking order.

The app, executable, Swift module, project, target, and scheme all use the name **SameWave**. The interface, documentation, export templates, AI insights, and generated titles are in English. Meeting text follows the selected source and target languages.

## Features

- Create and save a meeting before recording. Prepare a title, language pair, Markdown documents, meeting vocabulary, and custom insight prompts.
- Extract reviewable meeting terms from attached Markdown without adding them to other meetings or personal vocabulary. Attachment alone stays local.
- Generate custom insights manually or automatically during recording. Keep every successful result with its time, prompt, exact source, and vocabulary.
- Browse earlier insights offline and deliberately generate versioned full meeting summaries after End. Full-input analysis never silently drops the start of the meeting.
- Capture system output with ScreenCaptureKit and microphone input with AVFoundation.
- Recognize both audio streams locally with Apple `SpeechAnalyzer`.
- Manage English product names, personal names, and acronyms through Settings > Vocabulary. With AI configured, generate vocabulary for review from one or more Markdown files to improve recognition and preserve terminology in refinement and insights.
- Select English or Simplified Chinese independently for source and target. Use local Apple Translation when they differ; display recognition directly when they match.
- Organize turns into Sections. Translated captions emphasize the target text with the source beneath it; same-language captions avoid duplicate text.
- Save preparation before recording and transcripts incrementally to SwiftData, with pause, resume, crash recovery, history, and Markdown export.
- Reopen the last selected meeting. Interrupted recordings reopen paused; prepared drafts remain drafts. A missing or deleted selection chooses a remaining meeting, or the empty state when none remain.
- Configure AI once in the AI Services settings tab. Insights, refinement, meeting titles, and Markdown vocabulary generation share that configuration, each with its own typed output contract.
- Use built-in Qwen and Kimi models that support Structured Outputs. Custom services accept a domain, a versioned URL, or a complete endpoint; Test Connection verifies a nested structured-output contract.
- Show both speakers' live captions during overlap and update translations as results arrive, even while speech continues.
- Manage recording, pausing, and ending through an explicit state machine. Drain audio and ASR before the final save, with a bounded wait for translation.

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

1. Click New Meeting to save a draft. Optionally prepare Meeting title, Context, Vocabulary, and AI Insights. Save or Return commits your title; a saved title prevents AI title generation during refinement.
2. To use AI, open Settings → AI Services, configure a provider/key and Model context window (tokens), and save. The default is 1,000,000 tokens; enter the selected model's supported window. Custom services also need a URL and model. Local captions and preparation work without AI.
3. Attach Markdown in Context, then Manage Vocabulary to extract and review terms or enter them manually. Settings > Vocabulary uses the same editor for personal terms. Extract sends document text explicitly; Add to Vocabulary saves only selected suggestions to the displayed scope. Done preserves unfinished work and extraction for this app session. Vocabulary saves are independent of AI settings. Extraction prioritizes abbreviations, personal names, and specialized terminology; it avoids ordinary words and preserves meaningful multiword names.
4. Choose the source and target languages, enable the microphone if needed, and Start. English recognizers use meeting plus personal vocabulary frozen at Start/Resume; edits during recording take effect at Resume.
5. Use a card's refresh icon or Custom Insights → Generate to update all editable insights, with up to six concurrent requests. Focused insights select source-supported information that changes the answer, decision, or next action, with no point-count quota. They reconcile later corrections, merge repeated claims, and retain independent commitments separately. With no relevant discussion, they give only a conclusion. Automatic updates are optional and require 45 seconds plus 80 new finalized characters. Custom cards appear above Meeting Overview.
6. Pause, resume, or End. Browse each insight's saved versions independently; new results preserve an older selection and remembered Key points expansion. If saving fails, use Retry Save before quitting.
7. After End, use Meeting Insights → Generate for Topics, Suggestions, Action Items, Decisions, and Open Questions, displayed directly as cards. Regeneration retains earlier versions. Export includes all saved insights and the transcript; refinement keeps original text available. Refinement, title generation, and manual insights continue when you switch meetings; each busy meeting shows a sidebar spinner. Progress and errors last for this app session, and completed results are saved to their originating meeting.

See the [V2 specification](doc/phase-2-spec.md) for complete behavior and the [validation report](doc/phase-2-validation.md) for tested coverage and remaining smoke checks.

## Data and privacy

Audio capture, speech recognition, Apple Translation, attachments, and meeting history are handled locally. Audio is neither saved nor uploaded. Importing an attachment and sending its text are separate actions. Explicit vocabulary extraction sends document content in batches without filenames; only confirmed spellings are stored as vocabulary. Meeting vocabulary does not automatically enter personal settings.

Insight generation sends the full original transcript through its cutoff, the custom prompt, and the complete applicable meeting/personal vocabulary to the configured service. Saved snapshots retain that exact input locally, including provisional text when used. Refinement sends personal vocabulary; titles send no vocabulary. Full summaries do not send documents or earlier insights as factual context. Documents are used for vocabulary extraction only in this release.

Model context window defaults to 1,000,000 tokens and remains user configurable in AI Services. Save applies the value to new insight requests; active requests and saved history retain their frozen configuration. Preflight conservatively estimates serialized bytes plus instructions, Schema, framing, and output allowance. This is not a tokenizer or automatic model-limit discovery. Oversized requests produce a local context-window error before sending, with no truncation; actual provider rejections remain separate. Choose a model with adequate capacity and configure its supported window; no compressed long-meeting fallback is implemented.

If the local SwiftData container cannot open, the app blocks new meetings and displays an error. It does not silently switch to memory storage and imply that data was saved.

The bundle ID is `com.plus.samewave`, shared by the UserDefaults and Keychain namespaces. Speech models are cached under `Application Support/SameWave/SpeechLanguageModel`. Settings, vocabulary, keys, and model caches from an older app identity are not read or migrated; moving from that identity requires reconfiguration and may require permissions again. Phase 2 adds meeting-owned artifacts and replaces the obsolete single-insight field; no legacy insight reader, dual write, or custom migration is provided. Existing data files are not manually deleted. The English display-name change retains the current bundle ID and storage namespaces.

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
