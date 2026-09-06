# Phase 2 Validation

- **Scope:** P2-R01–P2-R09 in the [accepted V2 specification](phase-2-spec.md).
- **Review date:** 2026-09-06.
- **Branch:** `phase2`, based on `origin/main` at `045dcfd` when reviewed.

This report describes the current implementation and repeatable acceptance coverage. Superseded UI proposals and their rationale remain in [DECISIONS.md](DECISIONS.md), rather than appearing as current release behavior here.

## Release invariants

- A saved meeting exists before capture. Preparation survives empty capture, startup failure, switching, and relaunch.
- Documents, confirmed terms, definitions, and snapshots belong to one meeting. Deletion cascades; remaining selection is passive.
- English recognizers freeze the same meeting-plus-personal vocabulary at Start/Resume. Meeting terms never mutate personal settings.
- Every successful insight appends its frozen input, result, cutoff, configuration, vocabulary, and timestamps. Selected historical versions remain selected.
- Manual work is independent of automatic gates. Six active insight requests share one cap; automatic work occupies at most one slot.
- Cancellation and ownership checks reject late replies. Generation/save failures retain prior history and allow local save retry.
- Full insight input includes original source through the cutoff or fails visibly before transmission; no truncation or hidden recent-only analysis occurs.
- Shared vocabulary actions commit to the displayed scope. Dismissal preserves unfinished vocabulary work; settings checks cancel without discarding editable preferences.

## Requirement coverage

| Requirements | Repeatable coverage | Main test files |
|---|---|---|
| P2-R01 | Draft creation/selection, separate creation/start dates, failed-start retention, empty finish, title ownership, on-disk reopen, cascade deletion | `MeetingWorkspaceTests`, `MeetingHistoryStoreTests`, `MeetingSelectionTests`, `MeetingTitleGeneratorTests` |
| P2-R02 | Managed files, limits and deduplication, Unicode request splitting, term-only review, explicit selective saves, isolation, retries, deletion and late replies | `VocabularyGeneratorTests`, `VocabularyImportControllerTests`, `VocabularyEditorStoreTests`, `SpeechVocabularySettingsTests`, `MeetingWorkspaceTests` |
| P2-R03–R05 | Definition snapshots, interval/content gates, one automatic slot, manual priority/provisional source, six-request batches, frozen provider/inputs, out-of-order replies and cancellation | `InsightEngineTests`, `InsightBatchTests` |
| P2-R06–R07 | Append-only history, immutable source/configuration, independent historical selection, persistent Key points expansion, offline reading, save retry and archived definitions | `InsightEngineTests`, `InsightPresentationTests`, `MeetingWorkspaceTests`, `MainViewRenderingTests` |
| P2-R08–R09 | Multipart summary versions alongside live history, full original source independent of refinement, early/late content beyond 6,000 characters, complete vocabulary, explicit budget rejection, export | `MeetingSummaryTests`, `InsightEngineTests`, `TranscriptExporterTests` |

The existing caption, translation, endpoint, provider, refinement, language, and identity suites remain part of the full test gate.

## Pre-PR review corrections

The review traced app assembly, Settings, Preparation, extraction, insight scheduling, persistence, rendering, and export. Invariants and failure scenarios were recorded before changes in the local `.build/v2-review-plan.md` note.

- **Repeated attachments near the meeting limit:** two copies of one new filename/content pair counted twice before deduplication. The regression reproduces a false capacity rejection. One ordered merge/limit implementation now validates distinct additions before either meeting or personal file state changes.
- **Mixed insight shapes:** an unsaved summary could hide saved focused points, and an unsaved focused result could disappear beside a saved summary. Native render regressions reproduced both. Each version now renders its own shape, with one selected-snapshot decode per body evaluation.
- **Settings request lifetime:** an old connection response could mark edited configuration Connected, and closing during model discovery could leave Fetch Models disabled. Draft-owned request tokens invalidate stale replies; actual Settings dismissal clears loading even when SwiftUI retains its sheet content. A typed model is preserved during discovery. Controlled providers and native-sheet tests cover these cases without using real credentials.
- **User title metadata:** user-named meetings now retain their date in sidebar metadata, matching AI-named meetings. A native render assertion covers the date.
- **Duplicate implementations:** shared term identity/new-term filtering and file rows now serve manual editing, extraction, Context, and both vocabulary scopes. Removed obsolete candidate-save helpers, unused importer accessors, an unused Inspector binding, and redundant schema declarations. Tests exercise current production entry points.
- **Documentation:** README is shorter, the specification records final accepted choices, and this report replaces accumulated iteration logs. Domain references describe the final vocabulary host, cards, concurrency, and asynchronous settings ownership.

## Native UI and performance coverage

Native AppKit/SwiftUI hosts render Preparation, empty state, offline insights, archived results, errors, prompt editing, and the shared vocabulary editor. Main-window fixtures include 1120×760 and 940×480; Settings and vocabulary sheets use 600×540. Settings tests exercise nested presentation, actual dismissal, Escape, retained drafts, focus, and extraction completion after closing.

- Mixed-height insight scrolling keeps document height and reading position stable with a regular outer ScrollView/VStack. Tests send native scroll-wheel events and add results without resetting reading state.
- The shared editor uses lazy fixed-height term rows within stable cards. A 300-term Settings fixture measured 102–114 ms per tab update/layout pulse before optimization, with 24 saved-term reads over eight switches. The final review run measured 11.5–15.6 ms (median 13.6 ms), with zero saved-term reads. Timing wraps the main-actor update, native layout, one task yield, and a second layout; it does not measure GPU presentation or guarantee latency on other machines.
- Long-list tests cover distant scrolling, bottom actions, invalid row edits, cancellation, stable content extent, tab switching, and reopening. Other fixtures cover twelve wrapping preparation chips and every Context filename/size in the read-only extraction list.

Local visual artifacts inspected during review include:

- `.build/v2-mixed-insights-focused-history.png`
- `.build/v2-mixed-insights-focused-unsaved.png`
- `.build/v2-user-title-sidebar.png`
- `.build/embedded-vocabulary-settings.png`
- `.build/preparation-vocabulary-context-files.png`

Artifacts and logs remain untracked build outputs. The tests recreate them; they are not repository dependencies.

## Final validation gate

Run from the repository root:

```sh
xcodegen generate
xcodebuild -project SameWave.xcodeproj -scheme SameWave -configuration Debug -derivedDataPath .build CODE_SIGNING_ALLOWED=NO build
xcodebuild -project SameWave.xcodeproj -scheme SameWave -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath .build CODE_SIGNING_ALLOWED=NO test
python3 scripts/check_english.py
git diff --check
```

- XcodeGen and unsigned Debug build passed. Logs: `.build/v2-review-build.log` and `.build/v2-review-tests.log`.
- Full XCTest: **176 passed, 0 failed, 0 skipped**, scheme `SameWave`, configuration Debug, destination `platform=macOS,arch=arm64`, macOS 26.6.2. Independently verified with `xcresulttool get test-results summary` for `.build/Logs/Test/Test-SameWave-2026.09.06_20-35-28-+0800.xcresult`.
- English copy and local Markdown links passed for 64 files; `git diff --check` passed. Generated Info.plist, entitlements, and project configuration have no changes.
- `./build.sh` passed, replaced `/Users/plus/Desktop/SameWave.app`, and launched it. Strict/deep signature verification passed for `com.plus.samewave`, signed by `Apple Development: Jiahao Zhang (NWJTN3DP9L)`, Team ID `UBF8T346G9`. The installed executable was running as PID 3322 at verification. Log: `.build/v2-review-install.log`. This verifies installation and process startup, not the real-service checks below.

## Remaining real-service smoke checks

Deterministic tests use local fixtures and controlled providers. Native rendering and installation checks do not prove audio capture, permissions, recognition improvement, model factual quality, or real-provider compatibility. This review does not transmit real meeting/document content.

1. Attach real Markdown using the system file picker; explicitly extract, edit/select, and save terms with the configured provider. Close/reopen the editor during extraction and restart after saving. Repeat in Settings and verify scope separation.
2. Capture system audio and microphone, check prepared English terminology, pause/resume after vocabulary changes, and verify English-to-Chinese and direct Chinese display. Compare representative names with and without vocabulary before claiming accuracy gains.
3. Run automatic and manual insights during real speech, including visible provisional text and a batch of more than six definitions. Browse an older version while results arrive.
4. End and reopen offline, generate/regenerate Meeting Insights, inspect all five visible parts, and export saved versions. Refine with and without a saved user title.
5. Verify preflight rejection for input beyond the configured budget and readable real-service errors. The conservative byte estimate does not replace the provider's tokenizer/window limits.

No custom storage migration is included. Previous single-insight readers and dual writes are removed; an unreadable database fails visibly and existing data files are not manually deleted.
