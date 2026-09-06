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

- Start and quit without speaking; the prepared workspace remains on relaunch.
- Select history and reopen: sidebar, stage, and insights still correspond to it even if a newer unfinished meeting exists.
- Quit/crash while recording: the last selected session restores paused. After switching among paused sessions, reopening selects the last one.
- New Meeting saves and selects a draft. Deleting the displayed meeting selects a remaining meeting and restores its draft/history/paused presentation without starting capture. Reopen to verify that selection persists. With no meetings, show the empty state without a synthetic sidebar row or capture dock.
- Time stops while paused and continues cumulatively after resume.
- Switching among multiple paused sessions creates no conflicting/duplicate Section IDs.
- End saves final lines, duration, and translations.
- Rapid stop during model startup/resume does not let late ASR/translation enter a later meeting.
- Simulated persistence failure does not unmount unsaved state or show false success.
- Deleting noncurrent history cascades through its relationship.
- Verify English export headings, speaker labels, date/count/duration, and retention of original/translated content.

### 8.4 AI and interface

- Without AI configured, the local pipeline remains fully usable.
- Settings opens as a native sheet from the app menu/Command-comma and nested preparation panels, then returns to its presenter. It shows AI Services and Vocabulary; AI copy names all four consumers.
- Leave an unsaved vocabulary draft, then Configure AI Services from insights/refinement. It selects AI directly without saving the draft. The vocabulary page's configuration action does the same.
- Scroll through full custom AI settings/privacy content with Save/Cancel always accessible. Unsaved drafts do not unlock AI; complete saved settings enable all consumers.
- Edit connection details during Test Connection and verify that the old response cannot show Connected. Close Settings during model discovery and reopen: the draft remains, loading is cleared, and Fetch Models is available. A model typed during discovery must not be overwritten by its response. Vocabulary extraction remains independent.
- Meeting extraction continues across panel closure/reopening and meeting switches, preserving edits and selections. Context owns attachments; Preparation previews up to twelve terms across wrapping rows. Manage Vocabulary opens the shared editor with all Context filenames and sizes in the same order, plus a route back to Context; that read-only list has no removal or body previews. Add to Vocabulary saves checked terms in place and retains unchecked terms; Done only dismisses. Verify manual term entry, no-new-terms feedback, and repeated in-card actions with long lists and retained reading position after reopening. Remove an attachment during extraction; the running input and confirmed terms remain intact. Delete its meeting and verify that late results cannot restore it.
- Settings Vocabulary directly renders the shared editor. Switch between Vocabulary and AI Services, including Configure AI Services, without opening another window/sheet or changing Settings dimensions. Choose Markdown only loads local temporary files; Extract sends them explicitly. Done closes Settings. Tab switching and dismissal preserve drafts, files, candidates, reading position, and extraction for the app session.
- With 300 saved terms, including long two-line spellings, switch Settings tabs and scroll to the bottom and back. Document height and reading position remain stable. Repeat while editing an invalid row, then cancel. The native performance test records update/layout timing and asserts that tab navigation does not reread saved terms; timing is evidence from the test machine, not a device-independent frame-rate guarantee.
- Multiple requests reveal terms incrementally. Edits, deselection, and saves during generation survive later duplicate results. Stop retains results; retry handles incomplete requests only. Verify compact progress and inline error reasons without request details.
- Leave manual vocabulary edits and an AI Services draft unsaved, then save selected generated terms. Only selected terms persist; manual and AI drafts remain pending. Reopen Settings and cancel AI edits; saved vocabulary must remain unchanged. Test manual multiline Add, saved-row Save/Cancel, Remove, duplicate feedback, and all-or-nothing invalid-line handling.
- 401, 429, timeout, and non-JSON responses show the appropriate English error.
- Dense commits respect 45-second/80-character automatic gates and one automatic slot. Standalone Generate Now starts immediately; Custom Insights Generate fills up to six concurrent requests, including any automatic work in that cap. Completion, failure, and individual Stop refill available capacity. Whole-batch Stop clears queued and active work. Every successful result is saved independently.
- Save a Preparation title with Save or Return, record and End, then refine: no title request should be sent. Reopen to verify persistence. With no saved title, refine and save a user title before its response returns; the late AI title must be discarded. Clearing a user title reuses any existing AI title, otherwise the next refinement may generate one.
- One failed refinement batch neither erases successful batches nor overwrites originals.
- Cross-language and same-language refinement prompts/fields differ correctly; direction follows the saved pair.
- Historical/full-summary input retains all original source or fails preflight explicitly. Early agreements and late revisions both enter the request.
- New meetings reject old live-insight writes.
- Newly generated insights/titles are English. Check main-window controls, Settings, and vocabulary review for clipped English text at supported window sizes. Narrow stages stack language selectors above capture controls; history actions expose full names through tooltips and accessibility labels.

## 9. Automated coverage

`Tests/` protects:

1. `CaptionStore` floor switches, six-sentence split, non-floor interim, restore IDs/context, generation.
2. `TranslationBridge` replacement, cross-Section order, idle drain.
3. `MeetingHistoryStore.sync/finish` upsert, stale deletion, and empty-workspace retention; draft/attachment on-disk reopen and cascade ownership.
4. Full insight context, explicit budgets, strict JSON Schema/evidence, automatic gates, manual priority, cancellation, history versions, and save retry.
5. Refinement line/character batch limits.
6. Vocabulary defaults, persisted empty state, whitespace cleanup, case-insensitive deduplication.
7. Fixed language labels, four pairs, bypass, persisted pair values.
8. Markdown file/request budgets, Unicode fragmentation, incremental delivery, two retries and continuation, term-only review/persistence, omitted filenames.
9. Import stop/retry/discard, non-destructive close, and stale-response isolation; retained edits/selections; save-time deduplication and draft isolation; native Settings tab switching/dismissal and review rendering.
10. AI key/URL/model validation, all four unconfigured consumers blocked, connection-test/discovery cancellation and stale replies, local vocabulary availability, tab navigation and settings rendering.
11. Immediate selection persistence, UUID-based history/paused restore, invalid/missing selection handling, consistency after switch/delete/end.
12. English identity, output templates, metadata, title/insight prompts, and selected-language preservation.

Hosted XCTest launches detect `XCTestBundlePath`: app assembly uses an in-memory history container, skips restoring personal meeting selection, and does not request speech/microphone permission. AI settings also avoid loading the real key. Tests create their own in-memory or temporary on-disk stores and controlled providers. Passing domain tests does not prove real capture, permission reuse, translation, or recognition accuracy; those remain signed-app smoke checks.

## Phase 2 acceptance

See [Phase 2 validation](phase-2-validation.md) for repeatable coverage and remaining signed-app smoke checks. Render preparation and offline history at 1120×760 and 940×480; verify cards, empty state, editors, vocabulary management, archive, and inline errors. Check independent older-result selection/expansion, mixed saved/unsaved result shapes, identity-stable color allocation, retained history after definition removal, partial extraction retry, and Save failures independent of network progress. Test late responses with a provider that deliberately ignores cancellation.
