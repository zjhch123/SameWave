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

Issue #18 (2026-09-08): XcodeGen, unsigned Debug build, and all 213 tests passed with `SameWave` on `platform=macOS,arch=arm64`. The signed desktop app was replaced and launched; its signature and process were verified. A native UI smoke check opened the sidebar Delete alert, verified its meeting name and removal scope, and confirmed that Return invokes Cancel while retaining the meeting and selection. Existing cascade-deletion and selection tests cover the coordinator invoked by the destructive action.

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

This checks English source copy, documentation, filenames, and local Markdown links. Chinese UI translations belong in `Sources/Resources/Localizable.xcstrings` and `InfoPlist.xcstrings`; tests and supported transcript labels may contain language fixtures. The audit also invokes `scripts/check_localizations.py` to verify complete English/Simplified Chinese entries, plural structure, and matching interpolation placeholders.

`SWIFT_EMIT_LOC_STRINGS` emits compiler-extracted keys during a build. After changing copy, sync `Localizable.xcstrings` with `xcrun xcstringstool sync` and the app target's `.stringsdata` files in `.build/Build/Intermediates.noindex/SameWave.build/Debug/SameWave.build/Objects-normal/arm64`. Translate new entries and remove stale ones. Summary part titles/empty messages are manual catalog entries because their English values also serve Markdown export. Do not localize user content, storage keys, language identifiers, Schema, or prompts.

After building changed UI copy or integrating UI changes from separate branches, also check compiler-extracted keys against the catalogs:

```sh
python3 scripts/check_localizations.py --stringsdata \
  .build/Build/Intermediates.noindex/SameWave.build/Debug/SameWave.build/Objects-normal
```

This reports source locations for keys missing from the catalogs, including alert titles and interpolated messages. Catalog-only checks cannot detect these omissions. Use extraction output from the fresh app build; an absent extraction directory is an error.

Run the full suite with `-testLanguage en -testRegion US`. Also run `AppLanguageSettingsTests`, `LocalizationTests`, `MainViewRenderingTests/testLocalizedGeneralLanguageChoices`, `MainViewRenderingTests/testLocalizedWorkspaceSettingsVocabularyAndSummary`, and `MainViewRenderingTests/testLocalizedGeneratedInsightContent` using `-testLanguage zh-Hans -testRegion CN`; these verify compiled bundles, plural interpolation, metadata, insight request language across all generation paths, preserved content/export, and narrow native layouts in the actual app language.

Issue #17 (2026-09-08): XcodeGen, unsigned Debug build, and the source/link/translation audit passed. `SameWave` on `platform=macOS,arch=arm64` passed 219/219 tests with English/US and 6/6 localization/rendering tests with Simplified Chinese/CN. Chinese renders of preparation, settings, vocabulary, summary, and insight editing were inspected. The installed desktop app was replaced with `./build.sh`, verified against its existing certificate, and launched successfully. Native history metadata and opening/cancelling Settings were checked. Permission descriptions were verified in both compiled language bundles; existing TCC grants were not reset. This interface-only change does not claim a new audio/recognition accuracy benchmark.

In-app language selector follow-up (2026-09-08): XcodeGen, unsigned Debug build, and source/link/translation audit passed. `SameWave` on `platform=macOS,arch=arm64` passed 224/224 full tests with English/US and 11/11 preference/localization/rendering tests with Simplified Chinese/CN. All three selections were rendered in both interface languages. The signed desktop app was installed and launched; native UI checks verified selecting Chinese, closing/reopening Settings, applying Chinese after quit/reopen, applying English after quit/reopen, and returning to Follow System with no app override. General's Done/Return action closes the sheet. The installed signature and process were verified. Audio capture was not exercised for this settings-only change.

Insight language follow-up (2026-09-08): XcodeGen, unsigned Debug build, and source/link/translation audit passed. `SameWave` on `platform=macOS,arch=arm64` passed 227/227 full tests with English/US and 14/14 localization/rendering tests with Simplified Chinese/CN. Controlled-provider tests exercised automatic, manual, batch, and summary requests with a meeting language different from the interface, including result persistence, existing versions, and export. Chinese result, summary, and editor renders were visually inspected; both languages passed rendering assertions. `./build.sh` installed and launched the desktop app with its existing Chinese preference; signature/process checks and opening/cancelling the insight editor passed. No real AI service was called; model adherence remains a provider smoke check.

Deletion-dialog integration follow-up (2026-09-08): The compiler-coverage audit reproduced the two missing alert entries after merging #17 and #18, then passed with all 311 English/Simplified Chinese translations present. Compiled bundles preserve the meeting-name placeholder in both languages. XcodeGen and unsigned Debug build passed; `SameWave` on `platform=macOS,arch=arm64` passed 227/227 full tests with English/US and 14/14 Chinese localization/rendering tests. The native alert now retains its standard Cancel shortcut instead of overriding it with Return: manually verify that Return leaves the alert open, Escape dismisses it, and the named meeting and current selection remain intact. These checks passed on the signed desktop installation with the existing Chinese preference; signature and process checks passed. No existing meeting was deleted during the smoke check.

### AI switch and settings regression checks (issues #21, #24, #25)

Use the full English suite plus the Chinese localization/rendering selection, including `MainViewRenderingTests/testLocalizedAISettingsShowMasterSwitchAndCompactHelp` and `MainViewRenderingTests/testLocalizedPreparationSheetAlignsTitleAndDone`. The header test checks rendered text bounds to reject a separate empty button row. OCR checks readable helper text; inspect the native switch label and action on the signed app because OCR can confuse uppercase I with lowercase l.

On the signed app, open AI Services, turn AI off, and close Settings with Cancel. Reopen to verify the switch stays off while connection preferences remain intact; the inspector and vocabulary actions should offer Enable AI Services, with generation unavailable and saved content readable. Quit/reopen to verify persistence, then restore the original enabled state. Open Meeting Preparation from a saved meeting and verify title/Done alignment, scrolling with the header retained, and dismissal. Do not send real meeting text merely to test the switch. Controlled providers verify in-flight cancellation and late replies independently of network availability.

Validation on 2026-09-08: XcodeGen and the unsigned Debug build passed, with unchanged generated plist/entitlements. `SameWave` on `platform=macOS,arch=arm64` passed 237/237 full English/US tests and 16/16 Chinese/CN localization/rendering tests. Source/link/catalog audits and compiler-extracted localization coverage passed for 309 entries. The signed desktop app was replaced and launched, and its existing Apple Development signature and process were verified. Native Chinese checks confirmed the exact switch label, disabled generation/discovery/testing, retained connection values and saved results after Cancel and a verified process restart, the vocabulary enable-settings link, and restored enabled state. The preparation title and Done share a fixed row, remain visible while scrolling, and Done closes the sheet. No meeting content was edited and no real AI request was sent.

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
- Other → me → other: after at least one second without added remote words, the return opens a third paragraph before either recognizer finalizes. Repeated returns create later turns without copying cumulative prefixes; dense overlapping growth stays in two paragraphs.
- Overlap: added trailing words refresh activity; spelling/punctuation/middle-word corrections retain ownership without taking the floor or extending activity. Late finals commit every owned fragment once. Repeat with identities reversed, repeated words, Chinese, and retracted continuations.
- Long monologue: the seventh utterance opens a new Section on its first interim or direct final; translation retains context.
- Empty/nonlexical partials do not create Sections. Pause/end preserves fragments from all pending hypotheses, including sealed turns.
- Add, remove, and duplicate vocabulary terms; save and reopen to verify normalization/persistence.
- Saving vocabulary during recording leaves current recognizers unchanged; pause/resume activates the new list for both English streams.

### 8.2 Translation

- Growing interim text does not produce a long UI backlog. Before the first translation, source appears once as the primary caption. No pending, progressive, completed, or failed state displays Translating or a translation spinner.
- During continuous speech, earlier useful results appear while newer snapshots wait; late older replies never overwrite a newer displayed result.
- Both open and sealed Sections reach done when current source is translated; identical final/seal events do not restart work.
- Failure marks the Section failed, preserves source, and does not block pause/end indefinitely. Preparation failure also fails subsequent requests. A prepared request exceeding 15 seconds fails and cancels its session; pause/resume prepares a fresh one.
- Change language pairs while the mailbox is idle, then start/resume and verify new requests complete. Restore a paused meeting with a missing translation and verify source/failure, without Translating.
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
- Settings opens as a native sheet from the app menu/Command-comma and nested preparation panels, then returns to its presenter. It shows General, AI Services, and Vocabulary; AI copy names all four consumers.
- Leave an unsaved vocabulary draft, then Configure AI Services from insights/refinement. It selects AI directly without saving the draft. The vocabulary page's configuration action does the same.
- Scroll through full custom AI settings/privacy content with Save/Cancel always accessible. Unsaved drafts do not unlock AI; complete saved settings enable all consumers.
- Edit connection details during Test Connection and verify that the old response cannot show Connected. Close Settings during model discovery and reopen: the draft remains, loading is cleared, and Fetch Models is available. A model typed during discovery must not be overwritten by its response. Vocabulary extraction remains independent.
- Meeting extraction continues across panel closure/reopening and meeting switches, preserving edits and selections. Context owns attachments; Preparation previews up to twelve terms across wrapping rows. Manage Vocabulary opens the shared editor with all Context filenames and sizes in the same order, plus a route back to Context; that read-only list has no removal or body previews. Add to Vocabulary saves checked terms in place and retains unchecked terms; Done only dismisses. Verify manual term entry, no-new-terms feedback, and repeated in-card actions with long lists and retained reading position after reopening. Remove an attachment during extraction; the running input and confirmed terms remain intact. Delete its meeting and verify that late results cannot restore it.
- General initially shows Follow System. Choose English or Chinese, close and reopen Settings to verify the choice persists, then quit/reopen the app and verify menus, settings, and history metadata use that language. Choose Follow System and reopen again; the app-domain `AppleLanguages` override must be absent and the system language must be used. Changing language must leave meeting languages, saved content, global preferences, and pending AI/vocabulary edits intact.
- With each interface language active after relaunch, use a synthetic meeting whose speech language differs and generate a focused insight, an automatic overview, a custom-insight batch, and a full summary. New conclusions, points, and summary items should follow the app language while names and vocabulary retain their spelling. Reopen an earlier version and export: its text must retain its original language. Changing the language preference without relaunch must not change the active session's output language. Deterministic tests use a controlled provider to verify the sent contract, parsing, persistence, and rendering; actual model adherence requires this provider smoke check.
- Settings Vocabulary directly renders the shared editor. Switch between Vocabulary and AI Services, including Configure AI Services, without opening another window/sheet or changing Settings dimensions. Choose Markdown only loads local temporary files; Extract sends them explicitly. Done closes Settings. Tab switching and dismissal preserve drafts, files, candidates, reading position, and extraction for the app session.
- With 300 saved terms, including long two-line spellings, switch Settings tabs and scroll to the bottom and back. Document height and reading position remain stable. Repeat while editing an invalid row, then cancel. The native performance test records update/layout timing and asserts that tab navigation does not reread saved terms; timing is evidence from the test machine, not a device-independent frame-rate guarantee.
- Multiple requests reveal terms incrementally. Edits, deselection, and saves during generation survive later duplicate results. Stop retains results; retry handles incomplete requests only. Verify compact progress and inline error reasons without request details.
- Leave manual vocabulary edits and an AI Services draft unsaved, then save selected generated terms. Only selected terms persist; manual and AI drafts remain pending. Reopen Settings and cancel AI edits; saved vocabulary must remain unchanged. Test manual multiline Add, saved-row Save/Cancel, Remove, duplicate feedback, and all-or-nothing invalid-line handling.
- 401, 429, timeout, and non-JSON responses show the appropriate English error.
- Dense commits respect 45-second/80-character automatic gates and one automatic slot. Standalone Generate Now starts when a shared slot is available; Custom Insights Generate fills up to six concurrent requests, including any automatic work in that cap. Completion, failure, and individual Stop refill available capacity. Whole-batch Stop clears queued and active work. Every successful result is saved independently.
- Save a Preparation title with Save or Return, record and End, then refine: no title request should be sent. Reopen to verify persistence. With no saved title, refine and save a user title before its response returns; the late AI title must be discarded. Clearing a user title reuses any existing AI title, otherwise the next refinement may generate one.
- Start refinement/title generation in history, switch meetings, return while it runs, and leave it again until completion. Progress and sidebar activity remain with the original meeting, and results save there. Repeat with Custom Insights and Meeting Insights; run requests in two meetings and verify independent Stop/errors under the shared six-request cap. Delete a busy meeting and verify late replies cannot restore it. App relaunch retains completed results, without resuming unfinished jobs.
- One failed refinement batch neither erases successful batches nor overwrites originals.
- Cross-language and same-language refinement prompts/fields differ correctly; direction follows the saved pair.
- Historical/full-summary input retains all original source or fails preflight explicitly. Early agreements and late revisions both enter the request.
- New meetings reject old live-insight writes.
- Newly generated insights/titles are English. Check main-window controls, Settings, and vocabulary review for clipped English text at supported window sizes. Narrow stages stack language selectors above capture controls; history actions expose full names through tooltips and accessibility labels.

## 9. Automated coverage

`Tests/` protects:

1. `CaptionStore` symmetric returns before finalization, controlled inactivity boundaries, dense simultaneous growth, cumulative word ownership, native English snapshot replay, corrections/retractions, six-fragment split, frozen context, all-tail retention, restore IDs, progressive translation, and source deduplication.
2. `TranslationBridge` replacement, cross-Section fairness, 100-update progress, idle drain, cancellation/restart, preparation failure, empty/error responses, deadlines, and stale replies.
3. `MeetingHistoryStore.sync/finish` upsert, stale deletion, and empty-workspace retention; draft/attachment on-disk reopen and cascade ownership.
4. Full insight context, explicit budgets, strict JSON Schema/evidence, automatic gates, manual priority, cancellation, history versions, and save retry.
5. Refinement line/character batch limits; per-meeting progress, concurrent owners, navigation, title independence, deletion, partial failure, retry, and scoped persistence rollback.
6. Vocabulary defaults, persisted empty state, whitespace cleanup, case-insensitive deduplication, and extraction prompt priorities that preserve meaningful names.
7. Fixed language labels, four pairs, bypass, persisted pair values.
8. Markdown file/request budgets, Unicode fragmentation, incremental delivery, two retries and continuation, term-only review/persistence, omitted filenames.
9. Import stop/retry/discard, non-destructive close, and stale-response isolation; retained edits/selections; save-time deduplication and draft isolation; native Settings tab switching/dismissal and review rendering.
10. AI key/URL/model validation, all four unconfigured consumers blocked, connection-test/discovery cancellation and stale replies, local vocabulary availability, tab navigation and settings rendering.
11. Immediate selection persistence, UUID-based history/paused restore, invalid/missing selection handling, consistency after switch/delete/end.
12. English identity, output templates, metadata, title/insight prompts, and selected-language preservation.

Hosted XCTest launches detect `XCTestBundlePath`: app assembly uses an in-memory history container, skips restoring personal meeting selection, and does not request speech/microphone permission. AI settings also avoid loading the real key. Tests create their own in-memory or temporary on-disk stores and controlled providers. Passing domain tests does not prove real capture, permission reuse, translation, or recognition accuracy; those remain signed-app smoke checks.

## Initial live caption regression validation (2026-09-07)

For issues #12 and #13, XcodeGen and the unsigned Debug build passed, followed by 203/203 XCTest cases on scheme SameWave, destination `platform=macOS,arch=arm64`. Native test renders show both open speakers, progressive translation, completed translations without a busy label, and explicit source-preserving failures.

The signed desktop build passed strict signature verification and process checks. In a dedicated `Caption regression smoke test` meeting, synthetic English audio played through the system output and was also picked up by the microphone. Both capture streams displayed interim source and Chinese translations during playback. Pause drained recognition and cleared translation progress; resume accepted a new spoken passage and translated both streams. End saved the four substantive Sections, original English, and Chinese output in history. The retained smoke record contains synthetic text; no AI insights were requested.

This initial run verified local capture/recognition/translation and pause/resume/end. Its tests still expected one open Section per unfinished recognizer; the subsequent user report showed that this expectation allowed continuations to extend an older paragraph. It did not validate the corrected immediate three-turn behavior. See [the replacement decision](DECISIONS.md#dec-20260907-004) and current rendering requirements.

## Turn correction validation (2026-09-07)

Final XcodeGen and unsigned Debug build passed. Full XCTest passed 213/213 on scheme SameWave, destination `platform=macOS,arch=arm64`. The desktop app was replaced and launched with the existing Apple Development signature; strict signature verification and the installed executable's process check passed. After the Mac was unlocked, the final signed-app dual-input smoke test also passed. The source was unchanged during this additional validation, so the build and XCTest gate were not repeated.

In the dedicated `Final caption overlap verification` meeting, an 18-second synthetic English passage played through system output and was also picked up by the microphone. Both streams displayed growing source and Chinese translations without Translating or a translation spinner. The continuous overlap produced three readable paragraphs: two long speaker paragraphs and a short microphone continuation near the end, instead of the rejected per-word fragmentation. Pause retained both streams' final text. Resume accepted and translated a new passage on both streams; End saved five Sections and a cumulative duration of 1m 26s. Quitting and reopening the signed desktop app restored the same selected history record, all five Sections, English source, and Chinese translations. No AI insights were requested.

An independent native probe fed two Apple DictationTranscriber/SpeechAnalyzer streams with separate real-time audio buffers, including silence, and delivered their callbacks to the production CaptionStore with actual monotonic arrival times. Remote speech began at 1s, microphone speech at 5s, and remote speech resumed at 10s. At about 10.8s, the returning remote words opened a third Section. Before the 16s drain, the Sections were remote / mine / remote and neither recognizer had emitted a final result. Finalizing both analyzers retained all three fragments in order, sealed each Section, and left no pending interim text. This verifies an actual cumulative Apple recognition stream, rather than only simulated text events.

The two native checks cover complementary boundaries: the signed app exercises real capture, rendering, translation, and persistence; the independent probe isolates the two inputs and exercises Apple recognition plus production turn ownership, bypassing capture and translation. Both use synthetic English speech. They do not establish recognition accuracy, precise acoustic turn boundaries, or behavior for every natural conversation; the microphone had ordinary recognition errors during the overlap run.

Regressions require a returning speaker's new paragraph before either recognizer finalizes, while dense simultaneous growth remains in two readable paragraphs. The controlled monotonic clock tests the one-second recognition-inactivity boundary without sleeping. Cases also cover 20 repeated interruptions, corrections that do not refresh activity, late finals spanning several turns, repeated words, Chinese/mixed source, retractions, all-tail preservation, translation scheduling, and ordered persistence/export.

A native English DictationTranscriber probe using progressive long dictation and audioTimeRange showed one coarse interval per cumulative interim; per-word intervals appeared only in the final. A SpeechDetector probe alongside it returned no activity events, including with two-second silent intervals. Selected actual recognition text snapshots are replayed through production CaptionStore with interleaved replies and controlled arrival times. Native SwiftUI renders verify source-first pending captions in three paragraphs, progressive/completed translation, and explicit failure, all without Translating. These checks do not assert precise acoustic boundaries or perfect alignment of arbitrary recognizer rewrites.

A pre-final signed-app probe exposed excessive segmentation when both capture channels heard the same synthetic speech and every new word acquired the floor. That rejected behavior is retained only as a synthetic history record named `Turn boundary regression smoke test`; it motivated the dense-overlap regression and activity rule. It is not passing evidence for the final implementation.

The vocabulary scroll-retention fixture also exposed a desktop dependency during the full test gate: its synthetic wheel event inherited the real pointer location, outside the test window, and was ignored. It now positions the native clip view directly, as its existing bottom-of-list check already did, then verifies the same saved offsets across tab changes, arrivals, and reopening. This removes pointer dependence without changing vocabulary production code or relaxing assertions.

## Phase 2 acceptance

See [Phase 2 validation](phase-2-validation.md) for repeatable coverage and remaining signed-app smoke checks. Render preparation and offline history at 1120×760 and 940×480; verify cards, empty state, editors, vocabulary management, archive, and inline errors. Check independent older-result selection/expansion, mixed saved/unsaved result shapes, identity-stable color allocation, retained history after definition removal, partial extraction retry, and Save failures independent of network progress. Test late responses with a provider that deliberately ignores cancellation.
