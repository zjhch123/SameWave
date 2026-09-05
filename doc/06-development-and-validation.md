# Development and Validation

## 1. Environment

Current source requires:

- macOS 26+.
- Xcode 26+ / macOS 26 SDK.
- Swift 6.
- XcodeGen, to regenerate from `project.yml` before validation.
- The Apple Development signing identity configured in `build.sh` if installing with that script.

The main project has no Swift Package, CocoaPods, or Carthage dependencies. Run commands from the repository root.

## 2. Generate the project

```sh
xcodegen generate
```

[`project.yml`](../project.yml) declares targets, [`Info.plist`](../Sources/Resources/Info.plist), [`SameWave.entitlements`](../Sources/Resources/SameWave.entitlements), and build settings. Change it first, then regenerate `.xcodeproj` to prevent drift. `.gitignore` excludes generated `SameWave.xcodeproj`.

## 3. Unsigned build

For CI or source validation:

```sh
xcodebuild \
  -project SameWave.xcodeproj \
  -scheme SameWave \
  -configuration Debug \
  -derivedDataPath .build \
  CODE_SIGNING_ALLOWED=NO \
  build
```

The main target uses Swift 6 with `SWIFT_STRICT_CONCURRENCY=complete`. Do not resolve new concurrency diagnostics through unsafe Sendable annotations or reduced checking.

## 4. Unit tests and language audit

`SameWaveTests` is the XCTest target in the `SameWave` scheme. Run on macOS:

```sh
xcodebuild test \
  -project SameWave.xcodeproj \
  -scheme SameWave \
  -configuration Debug \
  -derivedDataPath .build \
  CODE_SIGNING_ALLOWED=NO \
  -destination 'platform=macOS'
```

Changes to pure logic or persistence mapping require tests, not compilation alone.

After copy or documentation changes, run:

```sh
python3 scripts/check_english.py
```

This checks app/documentation text and filenames for Chinese copy and verifies local Markdown file links. Chinese transcript fixtures and the refiner's recognition of Chinese speaker labels are intentional language data, not interface copy.

## 5. Install and launch

Under the continuing authorization in [`MEMORY.md`](../MEMORY.md), after development, build, and tests pass, replace and launch the desktop app by default without asking again. Verify the installed signature and process. Follow explicit exceptions in the current task.

Run [`build.sh`](../build.sh):

```sh
./build.sh
```

It:

1. Builds without signing.
2. Re-signs with the hardcoded development certificate.
3. Stops the existing desktop SameWave process.
4. Replaces `~/Desktop/SameWave.app`.
5. Launches the app.

A fixed bundle ID, installation path, and stable certificate keep TCC identity stable. The script stops processes and overwrites installation; it is not a read-only build command. Other developers must first configure their own `SIGN_ID`.

Bundle ID is `com.plus.samewave`; app, executable, module, project, and scheme all use `SameWave`. Moving from an older bundle identity requires reconfiguring settings/API keys and may require permissions again; older namespaces are not migrated. The English display-name change keeps the current bundle ID, settings, keys, and history. `build.sh` exits on build failure without signing/installing stale artifacts.

## 6. First-run permissions

Verify in order:

1. Speech recognition is authorized.
2. Microphone is authorized.
3. Screen recording is authorized.
4. First-use speech model resources are downloaded.
5. Resources for the selected English/Simplified Chinese translation direction are ready.

Permissions depend on signing identity. Frequently changing ad-hoc signatures or execution locations may cause the system to treat the app as new.

## 7. Common change entry points

| Requirement | Primary entry | Related checks |
|---|---|---|
| Segmentation/interruption | [`CaptionStore.swift`](../Sources/Meeting/CaptionStore.swift) | Coordinator, restore, export, state-machine tests |
| Domain/lifecycle types | [`MeetingModels.swift`](../Sources/Meeting/MeetingModels.swift) | Coordinator, SwiftData status, sidebar controls |
| Capture scope | [`SystemAudioCaptureSCK.swift`](../Sources/Capture/SystemAudioCaptureSCK.swift) | Permission copy, status |
| Microphone behavior | [`MicrophoneCapture.swift`](../Sources/Capture/MicrophoneCapture.swift) | Hot switching, pause/resume |
| ASR locale/results | [`NativeSpeechEngine.swift`](../Sources/Capture/NativeSpeechEngine.swift) | Language selection, Section commit semantics |
| English vocabulary | [`SpeechVocabularySettings.swift`](../Sources/Capture/SpeechVocabularySettings.swift) | Settings, model fingerprint, dual-stream snapshots, persistence tests |
| Translation frequency/order | [`TranslationBridge.swift`](../Sources/Meeting/TranslationBridge.swift) | Generation, final/done state |
| Translation context | [`CaptionStore.swift`](../Sources/Meeting/CaptionStore.swift) + `CaptureCoordinator.scheduleTranslation` | Delimiter recovery, latency |
| Session state | [`CaptureCoordinator.swift`](../Sources/Meeting/CaptureCoordinator.swift) | SwiftData status, selection, crash recovery |
| History model | [`MeetingHistory.swift`](../Sources/History/MeetingHistory.swift) | SwiftData schema, restore, export |
| New AI provider | [`LLMProviderConfig`](../Sources/AI/LLMProvider.swift) | Endpoint docs, model names, JSON contract |
| Insight schema | [`InsightModels.swift`](../Sources/Insights/InsightModels.swift) + prompt | Cards, persistence, export |
| Refinement | [`TranscriptRefiner.swift`](../Sources/Insights/TranscriptRefiner.swift) | Batch limits, partial success, glossary |
| Three-column assembly | [`MainView.swift`](../Sources/App/MainView.swift) | Translation modifier, Inspector width |
| History sidebar | [`MeetingSidebar.swift`](../Sources/App/MeetingSidebar.swift) | `@Query`, switching/deletion |
| Live/history stage | [`MeetingStage.swift`](../Sources/App/MeetingStage.swift) | Capture controls, export, refinement |
| Insight panel | [`InsightInspector.swift`](../Sources/App/InsightInspector.swift) | Engine, historical cache |

## 8. Minimal manual validation matrix

### 8.1 Live captions

- System audio only: remote works; disabled microphone creates no mine Section.
- Both streams: speaker labels remain correctly assigned.
- Other → me → other: Section order follows final commit order.
- Overlap: current single-floor serialization behaves as expected.
- Long monologue: the seventh final sentence opens a new Section; translation retains context.
- Noisy partials: non-floor interim does not cause unstable segmentation.
- Add, remove, and duplicate vocabulary terms; save and reopen to verify normalization/persistence.
- Saving vocabulary during recording leaves current recognizers unchanged; pause/resume activates the new list for both English streams.

### 8.2 Translation

- Growing interim text does not produce a long UI backlog.
- A late old generation cannot overwrite a newer translation.
- A sealed Section reaches done after a speaker switch.
- Failure marks the Section failed, preserves source, and does not block pause/end indefinitely.
- English→English and Simplified Chinese→Simplified Chinese send no requests and show no duplicate source.
- Both cross-language directions display the selected target. Menu names stay English and Simplified Chinese.
- If the translator rewrites the context delimiter, target-only translation remains available.

### 8.3 Sessions and history

- Start and quit without speaking; the empty-record behavior on relaunch is sensible.
- Select history and reopen: sidebar, stage, and insights still correspond to it even if a newer unfinished meeting exists.
- Quit/crash while recording: the last selected session restores paused. After switching among paused sessions, reopening selects the last one.
- Selecting a new meeting, first launch, or deletion of the saved selection shows a new meeting; other paused sessions remain selectable.
- Time stops while paused and continues cumulatively after resume.
- Switching among multiple paused sessions creates no conflicting/duplicate Section IDs.
- End saves final lines, duration, and translations.
- Rapid stop during model startup/resume does not let late ASR/translation enter a later meeting.
- Simulated persistence failure does not unmount unsaved state or show false success.
- Deleting noncurrent history cascades through its relationship.
- Verify English export headings, speaker labels, date/count/duration, and retention of original/translated content.

### 8.4 AI and interface

- Without AI configured, the local pipeline remains fully usable.
- Settings shows AI Services and Vocabulary; AI copy names all four consumers.
- Leave an unsaved vocabulary draft, then Configure AI Services from insights/refinement. It selects AI directly without saving the draft. The vocabulary page's configuration action does the same.
- Scroll through full custom AI settings/privacy content with Save/Cancel always accessible. Unsaved drafts do not unlock AI; complete saved settings enable all consumers.
- The Markdown picker precedes the separate window. Switching/closing Settings or hiding generation does not cancel; closing generation cancels and discards unsaved candidates.
- Multiple requests reveal terms incrementally. Edits, deselection, and saves during generation survive later duplicate results. Stop retains results; retry handles incomplete requests only. Expand details to verify real attempt durations/errors.
- Leave manual vocabulary edits unsaved, then save selected generated terms. Only new terms persist; manual drafts remain pending, and cancelling Settings does not undo import saves.
- 401, 429, timeout, and non-JSON responses show the appropriate English error.
- Dense commits allow only one insight request in flight, followed by one latest snapshot.
- One failed refinement batch neither erases successful batches nor overwrites originals.
- Cross-language and same-language refinement prompts/fields differ correctly; direction follows the saved pair.
- Long historical input sends only the latest 6,000 characters, preferring complete lines.
- New meetings reject old live-insight writes.
- Newly generated insights/titles are English. Check main-window controls, Settings, and vocabulary review for clipped English text at supported window sizes. Narrow stages stack language selectors above capture controls; history actions expose full names through tooltips and accessibility labels.

## 9. Automated coverage

`Tests/` protects:

1. `CaptionStore` floor switches, six-sentence split, non-floor interim, restore IDs/context, generation.
2. `TranslationBridge` replacement, cross-Section order, idle drain.
3. `MeetingHistoryStore.sync/finish` upsert, stale deletion, empty-record deletion.
4. Recent insight context, strict JSON Schema bodies, malformed-response rejection.
5. Refinement line/character batch limits.
6. Vocabulary defaults, persisted empty state, whitespace cleanup, case-insensitive deduplication.
7. Fixed language labels, four pairs, bypass, persisted pair values.
8. Markdown file/request budgets, Unicode fragmentation, incremental delivery, two retries and continuation, local provenance, omitted filenames.
9. Import stop/retry/close and stale-response isolation; retained edits/selections; save-time deduplication and draft isolation; native NSWindow hide/close semantics and review rendering.
10. AI key/URL/model validation, all four unconfigured consumers blocked, local vocabulary availability, tab navigation and settings rendering.
11. Immediate selection persistence, UUID-based history/paused restore, invalid/missing selection handling, consistency after switch/delete/end.
12. English identity, output templates, metadata, title/insight prompts, and selected-language preservation.

Domain tests do not start real audio, Apple Translation, or AI requests. However, XCTest uses the app as its host, and `AppDelegate.applicationDidFinishLaunching` still requests speech/microphone permissions. Alternating an unsigned temporary host and signed installation with the same bundle ID can mismatch TCC signature requirements and reprompt. Passing tests does not prove permission isolation or authorization reuse. Changes to those I/O boundaries require signed-app smoke tests; report unexecuted paths accurately.
