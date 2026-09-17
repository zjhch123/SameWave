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

Use the full English suite plus the Chinese localization/rendering selection, including `MainViewRenderingTests/testLocalizedAISettingsShowConnectionAndDisabledGuidance` and `MainViewRenderingTests/testLocalizedPreparationSheetAlignsTitleAndDone`. The header test checks rendered text bounds to reject a separate empty button row. OCR checks readable helper text; inspect the native switch label and action on the signed app because OCR can confuse uppercase I with lowercase l.

On the signed app, open General and verify that the AI title and subtitle share one native grouped row. Turn AI off and close Settings with Done. Reopen to verify the switch stays off while connection preferences remain intact; the inspector and vocabulary actions should offer Enable AI Services, with generation unavailable and saved content readable. Quit/reopen to verify persistence, then restore the original enabled state. Open Meeting Preparation from a saved meeting and verify title/Done alignment, scrolling with the header retained, and dismissal. Do not send real meeting text merely to test the switch. Controlled providers verify in-flight cancellation and late replies independently of network availability.

Validation on 2026-09-08: XcodeGen and the unsigned Debug build passed, with unchanged generated plist/entitlements. `SameWave` on `platform=macOS,arch=arm64` passed 237/237 full English/US tests and 16/16 Chinese/CN localization/rendering tests. Source/link/catalog audits and compiler-extracted localization coverage passed for 309 entries. The signed desktop app was replaced and launched, and its existing Apple Development signature and process were verified. Native Chinese checks confirmed the exact switch label, disabled generation/discovery/testing, retained connection values and saved results after Cancel and a verified process restart, the vocabulary enable-settings link, and restored enabled state. The preparation title and Done share a fixed row, remain visible while scrolling, and Done closes the sheet. No meeting content was edited and no real AI request was sent.

### Vocabulary settings consistency (issue #34)

Include `MainViewRenderingTests/testLocalizedVocabularySettingsKeepActionsVisibleInBothAppearances` in the Chinese selection. It renders empty, candidate review, and manual-entry states in light and dark appearance at 600×540, including Settings navigation and inline actions. The host sets native AppKit appearance as well as SwiftUI color scheme so system colors and headers are tested together. Existing vocabulary tests cover document metadata, explicit saves, invalid input, retained drafts, 300-term geometry, and candidate review across reopening.

Validation on 2026-09-09: XcodeGen and unsigned Debug build passed with unchanged generated plist/entitlements. `SameWave` on `platform=macOS,arch=arm64` passed 238/238 English/US tests and 17/17 Chinese/CN tests. Source, Markdown links, all 309 catalog entries, and compiler-extracted localization coverage passed. The 300-term fixture kept its extent and scroll offset stable and performed zero saved-term reads across eight tab switches. Native light/dark screenshots were inspected in both languages. `./build.sh` replaced and launched the desktop app; the existing Apple Development signature and desktop process were verified. Native Settings checks covered the grouped Vocabulary layout, file-picker cancellation, manual-entry expansion/collapse, saved-row edit cancellation, preserved reading position across tabs, and Done dismissal. No AI extraction request or audio capture was needed for this presentation change.

Validation against `main` with the history storage correction (2026-09-09): XcodeGen and unsigned Debug build passed. The `SameWave` scheme on `platform=macOS,arch=arm64` passed 243/243 full English/US tests and 28/28 Chinese/CN preference, localization, vocabulary rendering, and history tests. Source/link/catalog audits and compiler-extracted coverage passed for all 310 entries. The documentation merge preserves both sets of decisions and validation records; the PR diff remains limited to vocabulary presentation, its rendering test, and related documentation.

### History storage incident regression checks

See the [September 9 incident analysis](history-storage-incident-2026-09-09.md) for the timeline and native two-process reproduction. Keep every destructive fixture in a temporary directory. `MeetingHistoryStoreTests` must exercise actual foreign-model migration alongside the application-owned store, reject unexpected entity metadata before opening a container, preserve database/WAL bytes on rejection, and propagate corrupt-file and directory failures. Include `LocalizationTests/testUnexpectedHistoryModelErrorExplainsDataPreservation` when running the Chinese selection.

Validation on 2026-09-09: XcodeGen and unsigned Debug build passed. `SameWave` on `platform=macOS,arch=arm64` passed all 242 tests on the independent history branch; the Chinese/CN `LocalizationTests` and `MeetingHistoryStoreTests` selection passed 18/18. English source, Markdown links, all 310 catalog entries, and compiler-extracted localization coverage passed. The standalone native reproduction used two application bundles with different identifiers: the old shared path changed from one meeting to zero, while the explicit SameWave path retained its meeting. A fresh recovered-database copy opened through the newly guarded production store and passed six-model relationship checks, insight decoding, Markdown export, and a reversible save/delete operation.

`./build.sh` installed and launched the guarded desktop app with the existing Apple Development signature. Strict signature verification passed; the process's open files confirmed `SameWave/MeetingHistory.store`. Native UI checks showed the recovered history and preparation attachments/vocabulary before and after a normal quit/relaunch. SQLite integrity checks and comparisons of every field in all six model tables against the pre-investigation and pre-install snapshots passed, excluding only Core Data's `Z_OPT` row-version counters. Personal recovery content and evidence remain outside the repository. Audio capture and real AI requests were unnecessary for this storage change.

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
- Long monologue: sentence/clause/size boundaries limit each translation unit while adjacent same-speaker units share readable paragraphs. After the paragraph's soft length threshold, prefer a sentence ending; enforce the hard threshold between units if punctuation never arrives. Existing paragraph membership remains stable through revisions.
- Short unpunctuated finals: "I'd now like", "to", and "quote from" continue within the same unit, with immediate changed-source translation. Final commits and autosaves preserve each fragment once.
- Existing fragmented history: one speaker/time header covers adjacent units, source and target read continuously, and Original/Refined preserves grouping and stored content.
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
- Leave an unsaved vocabulary draft, then Configure AI Services from insights/refinement. It selects AI Services when enabled or General when disabled without changing vocabulary edits. The vocabulary page's configuration action does the same.
- Scroll through custom AI settings with Done always accessible. Edits save immediately; valid configuration enables all consumers. Invalid input stays visible and blocks new generation.
- Edit connection details during Test Connection and verify that the old response cannot show Connected. Close Settings during model discovery and reopen: preferences remain saved, loading is cleared, and Fetch Models is available. A model typed during discovery must not be overwritten by its response. Vocabulary extraction remains independent.
- Meeting extraction continues across panel closure/reopening and meeting switches, preserving edits and selections. Context owns attachments; Preparation previews up to twelve terms across wrapping rows. Manage Vocabulary opens the shared editor with all Context filenames and sizes in the same order, plus a route back to Context; that read-only list has no removal or body previews. Add to Vocabulary saves checked terms in place and retains unchecked terms; Done only dismisses. Verify manual term entry, no-new-terms feedback, and repeated in-section actions with long lists and retained reading position after reopening. Remove an attachment during extraction; the running input and confirmed terms remain intact. Delete its meeting and verify that late results cannot restore it.
- General initially shows Follow System. Choose English or Chinese, close and reopen Settings to verify the choice persists, then quit/reopen the app and verify menus, settings, and history metadata use that language. Choose Follow System and reopen again; the app-domain `AppleLanguages` override must be absent and the system language must be used. Changing language must leave meeting languages, saved content, global preferences, and pending AI/vocabulary edits intact.
- With each interface language active after relaunch, use a synthetic meeting whose speech language differs and generate a focused insight, an automatic overview, a custom-insight batch, and a full summary. New conclusions, points, and summary items should follow the app language while names and vocabulary retain their spelling. Reopen an earlier version and export: its text must retain its original language. Changing the language preference without relaunch must not change the active session's output language. Deterministic tests use a controlled provider to verify the sent contract, parsing, persistence, and rendering; actual model adherence requires this provider smoke check.
- Settings Vocabulary directly renders the shared editor using the same native grouped-form styling as General and AI Services. Check empty, suggestion review, and manual-entry states in English and Chinese, in both light and dark appearance; headings and all review actions must remain legible at 600×540. Expand selected files and open Add Terms: Add/Hide stays above the input. Switch between Vocabulary and AI Services, including Configure AI Services, without opening another window/sheet or changing Settings dimensions. Choose Markdown only loads local temporary files; Extract sends them explicitly. Done closes Settings. Tab switching and dismissal preserve drafts, files, candidates, reading position, and extraction for the app session.
- With 300 saved terms, including long two-line spellings, switch Settings tabs and scroll to the bottom and back. Document height and reading position remain stable. Repeat while editing an invalid row, then cancel. The native performance test records update/layout timing and asserts that tab navigation does not reread saved terms; timing is evidence from the test machine, not a device-independent frame-rate guarantee.
- Multiple requests reveal terms incrementally. Edits, deselection, and saves during generation survive later duplicate results. Stop retains results; retry handles incomplete requests only. Verify compact progress and inline error reasons without request details.
- Leave manual vocabulary edits pending, edit AI preferences, then save selected generated terms. AI preferences already persist; only selected terms are added and manual vocabulary input remains pending. Reopen Settings and verify both saved destinations. Test manual multiline Add, saved-row Save/Cancel, Remove, duplicate feedback, and all-or-nothing invalid-line handling.
- 401, 429, timeout, and non-JSON responses show the appropriate English error.
- Dense commits respect 45-second/80-character automatic gates and one automatic slot. Standalone Generate Now starts when a shared slot is available; Custom Insights Generate fills up to six concurrent requests, including any automatic work in that cap. Completion, failure, and individual Stop refill available capacity. Whole-batch Stop clears queued and active work. Every successful result is saved independently.
- Save a Preparation title with Save or Return, record and End, then refine: no title request should be sent. Reopen to verify persistence. With no saved title, refine and save a user title before its response returns; the late AI title must be discarded. Clearing a user title reuses any existing AI title, otherwise the next refinement may generate one.
- Start refinement/title generation in history, switch meetings, return while it runs, and leave it again until completion. Progress and sidebar activity remain with the original meeting, and results save there. Repeat with Custom Insights and Meeting Insights; run requests in two meetings and verify independent Stop/errors under the shared six-request cap. Delete a busy meeting and verify late replies cannot restore it. App relaunch retains completed results, without resuming unfinished jobs.
- One failed refinement batch neither erases successful batches nor overwrites originals.
- Cross-language and same-language refinement prompts/fields differ correctly; direction follows the saved pair.
- Historical/full-summary input retains all original source or fails preflight explicitly. Early agreements and late revisions both enter the request.
- New meetings reject old live-insight writes.
- Newly generated insights/titles are English. Check main-window controls, Settings, and vocabulary review for clipped English text at supported window sizes. Narrow stages stack language selectors above capture controls; history actions expose full names through tooltips and accessibility labels.

## Settings autosave smoke checks

Follow-up validation on 2026-09-10: moving Enable AI Services to General and unifying comparable title/subtitle control layouts passed XcodeGen, the unsigned Debug build, 253/253 full English/US tests, and 27/27 selected Simplified Chinese/CN tests with scheme `SameWave` on `platform=macOS,arch=arm64`. Native field tests verify that key, URL, model, and context-window controls disable and re-enable without losing values; navigation tests cover General while AI is off. The 314-entry catalog, compiler-extracted localization, source, and link audits passed. English/Chinese renders cover App Language, the AI switch and connection fields, insight automatic generation, manual vocabulary entry, and preparation actions. Light/dark entry renders retain leading-aligned text, and the 400-point preparation render keeps attachment actions complete while descriptions wrap. Preview assertions use stable first/middle/last text because OCR can confuse lowercase l with a vertical bar. Context groups its count and attachment button as separate accessible children. `./build.sh` replaced and launched the desktop app with its existing Apple Development signature; strict signature and installed-process checks passed. Desktop interaction confirmed disabled AI configuration, active Done/tab navigation, the General enablement destination, and opening/cancelling the attachment picker. The existing AI state and connection values were retained; no real API key was edited, AI request sent, or meeting content changed. Open Design was unavailable (`Transport closed`), so the user’s System Settings reference and public SwiftUI label APIs guided this adjustment.

Validation on 2026-09-10: XcodeGen and unsigned Debug build passed. The `SameWave` scheme passed 253/253 full English/US tests and 22/22 selected Simplified Chinese/CN tests on `platform=macOS,arch=arm64`, plus a focused credential write/delete failure-and-retry rerun after extending that case. Source/link and compiler-extracted localization audits passed for 312 entries. Native light/dark renders were inspected. The revised Open Design reference passed its 15 interaction checks and rendered review; its action ownership and grouped layout were compared with the native implementation. `./build.sh` replaced and launched the signed desktop app; strict signature and installed-process checks passed. Actual desktop typing saved the context window before leaving the field, invalid input stayed visible across Done/reopening, and each tab's Done closed correctly. The AI switch persisted without saving. The original enablement and context window were restored and verified after a process restart; the API key was untouched. No real AI request or audio capture was needed for this preference-only change.

For issue #32, open General, AI Services, and Vocabulary at 600×540 in English and Simplified Chinese. App Language, the AI master switch, connection-field instructions, and manual vocabulary entry use native title/subtitle labels with trailing controls. Check vocabulary input in light and dark appearance; multiline text stays leading-aligned. The insight editor and preparation actions use the same label hierarchy. At a 400-point preparation width, attachment actions remain fully visible while instructions wrap. The Context attachment button must remain separately accessible and open a file picker that can be cancelled. Every settings tab has one fixed Done action. AI preferences have no Save Changes, Revert, draft, or unsaved-change status. Toggle AI off/on in General: the switch persists before closing. With AI off, AI Services retains the configuration and disables every field, picker, menu, and action. Tab navigation and Done still work, and Enable AI Services entry points open General. Re-enable AI to edit a connection field and verify that its changes persist before closing. Done, Escape, and unconsumed Return only dismiss. Return in a connection field ends editing first. A vocabulary row's Escape cancels that row before the sheet closes; multiline Return remains local.

Enter valid and invalid context-window text while the field still has focus. Verify persistence immediately, then close/reopen and relaunch to confirm the displayed value is retained. Empty, nonnumeric, fractional, malformed grouping, and values outside 16,384–2,000,000 show inline validation and block new generation without retaining an older numeric value. Correct the input and verify availability returns immediately. Invalid input must not block other preferences from saving. A changed window applies to the next request; an existing request keeps its original input.

Edit connection details during Test Connection: late replies cannot report success for the new configuration. Model discovery saves its selected model immediately and preserves manual edits made during the request. Dismissal cancels service checks and clears loading; vocabulary extraction continues. Simulated Keychain write/delete failures must show an inline error with Retry, preserve the input and prior stored key, and block new generation until persistence succeeds. Never alter the real API key for a smoke test.

## Default insights validation (issue #22)

On 2026-09-10, final XcodeGen and unsigned Debug build passed. Scheme `SameWave`, destination `platform=macOS,arch=arm64`, passed all 262 XCTest cases with English/US and 19 focused default/settings/rendering cases with Simplified Chinese/CN. The English-source/link audit and all 326 UI/permission translations passed, including compiler-extracted key coverage. Native light/dark list, empty-state, and editor renders were inspected.

The final `./build.sh` installation replaced and launched `~/Desktop/SameWave.app` with the existing Apple Development identity. Strict signature and installed-process checks passed. With AI off, the signed-app smoke check added and saved a default, verified its fields after relaunch, canceled an edit, saved a changed title/mode, and removed the test default. A new draft received independent title/prompt/focus/automatic values, retained them after default edits/removal and relaunch, and left a pre-existing draft unchanged. The global list was restored to Meeting Overview and the original meeting selection restored. One synthetic draft, `Default Insights validation`, remains for inspection; no audio was captured or AI request made.

The signed accessibility check caught a multi-action `LabeledContent` row omitting its buttons, especially after returning to one item. An explicit stack with contained children now exposes named Edit and Remove controls for one or multiple items and after deletion. An attempted in-process accessibility test could not observe any SwiftUI children, including Done, so it was not used as evidence; hosted rendering tests and the signed app's real accessibility tree verify complementary boundaries. The workflow rule now requires this check for native rows with multiple actions.

Use Settings > Insights to add a default with a title, prompt, latest-exchange focus, and automatic generation enabled. Cancel an edit and confirm the saved content remains; save a new edit and reopen Settings to verify it. Create a new meeting and inspect the copied definition. Change or remove the default, then verify the existing meeting keeps its own configuration and the next meeting uses the updated list. Quit and reopen to confirm both scopes persist. Default management must remain available with AI disabled and make no AI requests.

Deterministic coverage includes absent versus saved-empty preferences, all fields and trimming, invalid edits, preserved malformed/duplicate data with explicit reset, both creation entry points, distinct identities, bidirectional edit isolation, and on-disk history/snapshot retention. Native tests cover item Cancel, failed Save and retry, Return/Escape ownership across all four tabs, and English/Simplified Chinese list, empty-state, and editor rendering in both appearances. Tests use isolated UserDefaults suites and in-memory or temporary history stores.

## Simple Mode validation (issue #42)

On 2026-09-17, integration with main commit `7e720da` passed XcodeGen and the unsigned Debug build. Scheme `SameWave`, destination `platform=macOS,arch=arm64`, passed 315/315 full English/US tests and 33/33 selected Simplified Chinese/CN tests. Source/link and compiler-extracted localization audits passed for all 333 UI/permission entries. The combined suite includes shared Simple Mode/full-window rendering and scrolling, live paragraph stability, native history performance, retained-window lifecycle, and background opacity regressions.

`./build.sh` replaced and launched the desktop app using its existing signature. Strict signature and installed-process checks passed. The dedicated `Simple Mode main integration validation` meeting captured a real system-audio playback of three English sentences with Chinese translations and no configured insights. After installation, both window modes exposed the complete bilingual paragraph and Speaker label in the signed app's accessibility tree, along with the individually named microphone, pause/resume, End, opacity, and full-window actions in Simple Mode. The meeting remains paused for inspection.

Native checks covered the header and View-menu entries, Command–Shift–T, Command–W, Show Full Window, the absence of language selectors/traffic lights, and the opacity popover's Escape handling. Opacity reached 0%, 50%, and 100%; 50% survived relaunch, and the final preference was restored to 85%. The panel resized horizontally and retained geometry across switches. Its accessibility tree remained available while TextEdit was frontmost and entered full screen. This does not establish visual overlap for every full-screen/display configuration; display disconnection and VoiceOver were not exercised.

`SimpleCaptionTests` compares the complete bilingual paragraph rendered by Simple Mode and the full window, checks Speaker labels, and scrolls a 36-caption conversation from its latest text to its beginning while new source arrives. Shared `CaptionPresentationTests` cover grouping, height reservation, and automatic following; `CaptionStabilityTests` cover late splits and stale combined-target rejection. `MainWindowPresentationTests` covers preparation/empty/history entry rejection, ending before attachment, automatic full-window restoration after End, delayed native attachment, retained hosts and frame, repeated mode changes, a 440×180 panel with long captions, explicit full-window restoration, borderless panel properties, close handling, and unchanged session/translation ownership. Native bitmap tests verify background alpha at 0%, 50%, and 100% while retaining foreground rendering. Bilingual rendering checks header/menu entry visibility through preparation, pause, and End, plus complete original/translated text, pending and failed source display, long content, and the opacity popover in both appearances.

In the signed app, confirm preparation and ended history have no header, View-menu, or menu-bar entry and Command–Shift–T cannot enter Simple Mode. Start a meeting, then enter using each available entry point and Command–Shift–T. Verify separate accessible microphone, pause/resume, end, opacity, and full-window actions, with no language selectors or traffic-light controls. Pause must retain all mode entry points; End must restore the existing full window and hide them again. Command–W returns to the existing full window. Move and resize the panel to 440×180, switch modes, and verify independent retained geometry. Adjust opacity at its endpoints and an intermediate value; subtitles and controls remain opaque, and the preference survives reopening and relaunch.

Start a dedicated meeting in the full window, then play known synthetic speech through system audio with the microphone off. Verify every sentence, original text, translation, paragraph grouping, and speaker label remains available in both modes. Pause, change the microphone setting, resume, play another passage, and end. Confirm both passages in saved history after automatic return to the full window. Scroll upward in long captions, verify new content does not move the reading position, and return to the bottom to follow updates again. Multi-display disconnection, other apps' full-screen Spaces, and VoiceOver require separate native checks when those environments are available.

## 9. Automated coverage

`Tests/` protects:

1. `CaptionStore` symmetric returns before finalization, controlled inactivity boundaries, dense simultaneous growth, cumulative word ownership, native English snapshot replay, corrections/retractions, sentence/clause preference, short final continuation, temporary/late punctuation, prefix deadlines, split invalidation, committed/interim conservation, restore IDs, progressive translation, and source deduplication. `CaptionParagraphTests` covers the reported history fragments, stable membership, sentence/length/speaker/time boundaries, Chinese joining, and refinement independence. `CaptionPresentationTests` checks grouped live/history text, earlier-word and source positions, unchanged preceding-paragraph pixels, promotion height, initial bottom positioning, retained history reading, and resumed following through the native scroll view. History tests preserve source and row IDs across autosaves, short finals, internal splits, and finalization.
2. `TranslationBridge` first-request responsiveness, sustained-input cadence, latest-source replacement, cross-Section fairness, 100-update progress, idle drain, cancellation/restart, preparation failure, empty/error responses, deadlines, and stale replies.
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

Hosted XCTest launches detect `XCTestBundlePath`: app assembly uses an in-memory history container, skips restoring personal meeting selection, and does not request speech/microphone permission. AI settings also avoid reading or writing the real key; injected writers cover persistence failure and retry. Tests create their own in-memory or temporary on-disk stores and controlled providers. Passing domain tests does not prove real capture, permission reuse, translation, or recognition accuracy; those remain signed-app smoke checks.

Persistent history uses `~/Library/Application Support/SameWave/MeetingHistory.store`. Regression coverage verifies reopening with a neighboring unrelated `default.store`, preservation of that unrelated file, and visible failure when the application directory cannot be created. Never run recovery experiments against the live history: preserve the database and sidecars, work on copies, validate all model relationships and insight decoding with the application, and install only a verified recovered copy. Do not restore old backups over newer data without reconciling their contents.

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

## Live caption stability validation (2026-09-17)

This validation records [DEC-20260917-001](DECISIONS.md#dec-20260917-001), whose per-unit visual rows and unconditional final-result sealing were subsequently superseded by [DEC-20260917-002](DECISIONS.md#dec-20260917-002). Regression fixtures exercised the production store, translation mailbox, native caption views, and SwiftData history. Scripted text and controlled translation completions verify state invariants; actual audio and Apple Translation require the separate signed-app check. Local logs and native render artifacts are in the ignored `.build/caption-stability/` directory.

XcodeGen and the unsigned Debug build passed. Scheme `SameWave` on `platform=macOS,arch=arm64` passed 273/273 full English/US tests and 22/22 selected Simplified Chinese/CN preference, localization, and native rendering tests. Source/Markdown-link checks and all 326 UI/permission translations passed, including compiler-extracted key coverage. Caption rendering tests compare unchanged previous-row pixels and native document geometry through draft translation and promotion; they also verify actual scroll bounds after history reading and resumed following. The Chinese selection uses the bilingual rendering cases; English-only text assertions belong to the English run.

`./build.sh` installed and launched the desktop app with its existing Apple Development signature. Strict signature and desktop-process checks passed. In `Live caption stability verification`, a locally synthesized 33.56-second English passage went through system output, actual Apple Speech, and actual Apple Translation. During playback, source and Chinese targets appeared before the passage finished, earlier captions remained independently translated, and the newest draft used secondary color. The microphone also captured the beginning; the user then manually switched it off. The check continued with system audio. Pause preserved the transcript; Resume translated another spoken passage. While the view was manually scrolled to the beginning, new source and translations appeared in the data without moving that reading position. Returning to the bottom showed the new captions. End saved 13 Sections and 2m 46s of session time.

In `Chinese caption stability verification`, actual Chinese speech recognition displayed growing source directly, split the unpunctuated passage into two captions, and showed no duplicate source line. End saved both captions and 1m 21s of session time. A normal quit/relaunch produced a new desktop process and restored the selected English record with all 13 Sections, original source, and Chinese targets; the Chinese record retained its two-caption metadata. Neither synthetic test meeting had configured insights, and no AI generation was requested. Recognition mistakes were visible in these real audio checks; they are not an ASR accuracy benchmark. Active-clause translations and genuine ASR corrections remain revisable, and late punctuation need not produce the same boundaries as the written speech fixture.

## Caption paragraph validation (2026-09-17)

[DEC-20260917-002](DECISIONS.md#dec-20260917-002) separates visible paragraphs from independent translation units and retains short unpunctuated final fragments within a unit. XcodeGen and the unsigned Debug build passed. Scheme `SameWave`, destination `platform=macOS,arch=arm64`, passed 286/286 English/US tests and 24/24 selected Simplified Chinese/CN tests. Source/link checks and all 326 UI/permission translations passed, including compiler-extracted coverage. Logs are in the ignored `.build/caption-paragraphs/` directory; native rendering fixtures are under `.build/caption-stability/`.

Regression coverage includes the reported seven fragments, changed-source translation between short finals, committed-prefix corrections and pause retention, bounded repeated finals, Chinese joining, sentence-preferred paragraph breaks with a hard limit, stable membership after corrections/retractions, speaker/time boundaries, and original/refined group independence. Native rendering verifies all seven reported fragments fit in a continuous paragraph with one timestamp, earlier words and source retain their vertical positions through shorter targets and promotion, and actual scroll bounds retain manual reading before resuming following. In-memory SwiftData verifies that repeated short finals update one persistent line across autosaves and create another line only at the next unit boundary.

The final `./build.sh` installation replaced and launched `~/Desktop/SameWave.app` with the existing Apple Development identity. Strict signature and desktop-process checks passed. The actual `TED Vancouver Closing Speech` record retains 28 stored Sections and 1m 42s duration while rendering as three paragraphs. Its Original and Refined views retain the same groups and their respective text. The native accessibility tree and rendered desktop pixels confirm the shared paragraph headers and continuous source/target layout.

In `Caption paragraph verification`, a 17.79-second locally synthesized English passage went through system output, actual Apple Speech, and actual Apple Translation. Chinese targets appeared during playback and updated within shared paragraphs. The source-only tail was visible while awaiting translation. Pause retained the source; End saved six independent units shown in two paragraphs, with 1m 31s session duration. Other audible system output was also captured before and after the prepared passage; this run verifies the pipeline and presentation, not isolated recognition or translation accuracy. In `Chinese paragraph verification`, 17.60 seconds of synthesized Chinese speech produced growing source directly, with two units displayed as one paragraph and no duplicate source row. End retained the paragraph and 53s duration. The microphone remained disabled for both checks. Neither meeting had configured insights, and no AI generation was requested. Recognition errors and contextual translation repetition remained visible; paragraph grouping preserves content rather than correcting its wording. A normal quit/relaunch produced a new desktop process, restored the selected TED history record in Refined mode with its three paragraphs, and retained both new verification records and their counts/durations.

## Caption boundary and request validation (2026-09-17)

[DEC-20260917-003](DECISIONS.md#dec-20260917-003) adds independent boundary confirmation, late partitioning of the newest active unit, direct unit translation, and a bounded subsequent-request cadence. The focused production-state suite passed 67/67. Cases cover temporary punctuation lasting beyond the former deadline, unchanged prefixes during suffix growth, late English/Chinese boundaries, combined-target invalidation including stale failures, committed/interim ownership through finalization and stop, natural boundaries before the size guard, batched long speech, overlap ordering, first-request timing, continuous-input dispatches, and incremental history rows. Logs and replay artifacts are in the ignored `.build/caption-refinement/` directory.

An isolated comparison used the same 17.79-second synthesized English audio file as the paragraph check. The file was converted to the format requested by Apple SpeechAnalyzer, delivered in real-time 100 ms buffers to `DictationTranscriber.progressiveLongDictation`, and followed by 1.5 seconds of silence and finalization. It did not capture microphone or unrelated system sound. The resulting actual Speech events and arrival schedule were then replayed through the baseline and updated production CaptionStore/TranslationBridge, with actual local Apple Translation. Both language models were installed and Translation preparation finished before replay. The baseline executable was compiled before source edits. The replay uses the same request assembly and Translation calls as each version; it bypasses ScreenCaptureKit and SwiftUI, so signed-app checks remain separate.

Two baseline replays and two replays with the final 400 ms dispatch cadence produced:

| Observation | Baseline | Updated |
|---|---|---|
| First translated output after playback start | 714–1,065 ms | 739–945 ms |
| Translation requests | 66–67 | 48 |
| Final translation units | 4 | 2 |
| Occurrences of the repeated earlier-word clause | 2 | 1 |
| Target changes that removed an existing suffix | 32–33 | 33 |
| Largest removed target suffix | 33 characters | 55 characters |
| Total removed target characters | 445–446 | 749–752 |
| Failed translation requests | 0 | 0 |

The final joined source was identical in both versions. The baseline split "while the current" from "sentence continues to grow" and repeated the earlier-word clause in adjacent translations. The updated units retained that dependent phrase together and translated the clause once. These results support fewer requests, improved completeness, and removal of this contextual repetition; they do not demonstrate fewer textual rewrites. Larger active units increased individual and cumulative changed text in this sample. The rewrite calculation compares each unit's previous target with its next target, counts the removed suffix after their longest common prefix, and includes invalidation when a unit is split. It does not measure pixels, scrolling, readability scores, or linguistic accuracy. First-response timing varies with framework execution and process scheduling; the small sample is not a latency guarantee. ASR omitted several spoken sentence boundaries, and the app does not invent missing punctuation.

The final gate, including the history scrolling regression below, passed XcodeGen, the unsigned Debug build, 296/296 English/US XCTest cases, and 25/25 selected Simplified Chinese/CN cases on scheme `SameWave`, destination `platform=macOS,arch=arm64`. English source/Markdown links and all 326 UI/permission translations passed, including compiler-extracted coverage. `./build.sh` replaced and launched the desktop app with the existing Apple Development identity; strict/deep signature and desktop-process checks passed.

In the signed `Caption boundary verification` meeting, the 17.79-second English passage produced growing source and Chinese translations during system-audio playback. Pause retained all received content. Resume accepted the 9.67-second continuation while preserving the earlier paragraphs. End saved six Sections, displayed in two paragraphs, with 2m 7s session duration. The microphone was disabled and no insights were configured. Ordinary recognition errors remained visible; this is pipeline validation, not an accuracy benchmark.

The final installed app also recognized a 17.60-second Chinese system-audio passage in `Chinese boundary verification`, with both languages set to Simplified Chinese, the microphone disabled, and no insight definitions. The displayed paragraph contained source directly with no secondary duplicate. The meeting was subsequently observed paused at 1m 16s with its text retained and was left in that state. The native text observation occurred after playback, so this Chinese check does not measure first-output latency or verify End for that meeting.

## History scrolling validation (2026-09-17)

[DEC-20260917-004](DECISIONS.md#dec-20260917-004) removes lazy height estimation and live height observation from saved transcript layout. The system's September 17 hang report recorded 34.35 seconds of unresponsiveness at 15:31. Its main-thread samples continuously processed SwiftUI/AttributeGraph layout, including lazy item phase updates and scroll geometry. Sampling the relaunched desktop process showed an idle event loop, so the full hang duration was not reproduced in the controlled test.

The native 48-paragraph bilingual regression reproduced scroll instability before the fix: unchanged document height changed from 9,898 to 17,048 points in the narrow Original case, and some requested reading offsets moved after layout. After the fix, the same test retained document height and exact reading offsets through repeated upward/downward scrolling, Original/Refined changes, and widths of 620 and 1,000 points. The existing live caption geometry and automatic-follow tests also passed. Logs are in the ignored `.build/caption-refinement/` directory.

The installed app retained the reported 33-Section, 2m 2s meeting and its five paragraphs. Both Original and Refined modes responded to repeated scrolling and reached the final text. A separate 157-Section, 95m 44s record loaded and scrolled through its refined transcript to the final paragraph. Native rendered checks confirmed text remained visible. These checks cover the reported reading path and the deterministic geometry defect; they do not establish a universal bound on opening arbitrarily large archives.

## Long-history opening validation (2026-09-17)

[DEC-20260917-005](DECISIONS.md#dec-20260917-005) replaces per-paragraph SwiftUI history with one native AppKit text document and prepares a single Section index. A bilingual 500-Section fixture uses mixed text lengths, speaker changes, and time gaps, with distinct original/refined source. The native host measures opening and Original/Refined changes through layout and visible drawing. The final regression also checks every Section marker, complete character layout, and the last glyph's position within the measured document. It does not satisfy the timing gate with missing or deferred text. Logs are in the ignored `.build/history-performance/` directory.

| Local Debug measurement | Open | Refined | Original |
|---|---:|---:|---:|
| Eager SwiftUI history before this change | 1,463.95 ms | 668.24 ms | 850.76 ms |
| Single index with eager SwiftUI | 887.10 ms | 297.96 ms | 468.63 ms |
| Native document, final English/US suite | 99.74 ms | 92.51 ms | 92.69 ms |
| Native document, final Chinese/CN suite | 103.43 ms | 97.54 ms | 100.24 ms |
| Native document, pre-PR English/US repeat | 164.31 ms | 91.41 ms | 91.25 ms |
| Native document, pre-PR Chinese/CN repeat | 175.07 ms | 96.94 ms | 98.04 ms |

These are local fixture measurements, not production telemetry or a bound for all archive lengths. Initial SwiftData disk faults, other meeting panels, platform load, and longer documents can add latency. The regression gate requires each 500-Section operation to complete within 500 ms on this test machine.

The pre-PR repeat also passed all 301 English/US and 30 selected Chinese/CN tests with the caption render directory initially absent. Native rendering tests create their ignored output directory before saving images, so they do not depend on artifacts from earlier runs.

XcodeGen and the unsigned Debug build passed. Scheme `SameWave`, destination `platform=macOS,arch=arm64`, passed 301/301 English/US tests and 30/30 selected Simplified Chinese/CN tests. English source/Markdown links and all 326 UI/permission translations passed, including compiler-extracted coverage. Native tests verify mounted SwiftData refinement and line insertion, source echoes, selection/copy through the text view's supported pasteboard types, unchanged-update selection and reading position, and long-to-short/empty replacement. The existing 48-paragraph Original/Refined regression retains document height and exact requested offsets through repeated scrolling at 620- and 1,000-point widths. Live caption promotion, source-baseline, and automatic-follow checks also pass.

`./build.sh` replaced and launched the desktop app using its existing Apple Development identity. Strict/deep signature verification and the installed desktop process check passed. The signed app restored `Substrate KS - Ingestion & Crawler` with 157 Sections and 95m 44s duration. Switching to the 24-Section `Q4 Product Priorities` record and back replaced the text, returned to the beginning, and retained the long meeting's first and final paragraphs. Original and Refined both responded to long downward/upward scrolls and reached the end. Hiding and restoring the sidebar changed the available text width; the final source and translation remained visible, with the scroller reaching the document end. Rendered desktop checks confirmed headers, primary/secondary styles, and bottom spacing. Native text selection exposed the chosen final sentence in accessibility, and its context menu offered Copy; XCTest verified actual copying through a unique named pasteboard. The app was left on the long record in Refined mode, at the beginning, with the original sidebar layout restored.

## Phase 2 acceptance

See [Phase 2 validation](phase-2-validation.md) for repeatable coverage and remaining signed-app smoke checks. Render preparation and offline history at 1120×760 and 940×480; verify cards, empty state, editors, vocabulary management, archive, and inline errors. Check independent older-result selection/expansion, mixed saved/unsaved result shapes, identity-stable color allocation, retained history after definition removal, partial extraction retry, and Save failures independent of network progress. Test late responses with a provider that deliberately ignores cancellation.
