# SameWave Decision Records

This file records adopted decisions with lasting project impact, explaining why they were made. Domain references and source describe current architecture and implementation. This is not a changelog, requirements backlog, or task list.

Naming maintenance: historical project identifiers and file paths use current SameWave names. Original decision dates, statuses, and validation conclusions are preserved; mechanical updates do not imply that historical validation used the new names. Historical references to removed files are retained as code paths rather than broken links. English translations preserve superseded behavior as history.

## Maintenance rules

- Scope: important choices in product behavior, architectural boundaries, core state machines, data, security/privacy, dependencies, and engineering workflow.
- Timing: record evaluated, adopted decisions before task completion. Do not mark proposals or unverified ideas `Accepted`.
- Ordering/IDs: newest first; use `DEC-YYYYMMDD-NNN` and never reuse an ID.
- Status: `Accepted` or `Superseded`. Preserve replaced decisions and identify their replacements.
- Content: context, decision, rejected alternatives, rationale/tradeoffs, impact, validation, relevant files.
- Granularity: omit mechanical renames, ordinary bug fixes, implementation steps uniquely determined by requirements, and reversible local details.
- Consistency: update relevant domain references, requirements, source, and tests together. Current source and explicit requirements resolve conflicts; correct documentation accordingly.

---

<a id="dec-20260905-006"></a>
## DEC-20260905-006: Use English throughout the product and documentation

- **Date:** 2026-09-05
- **Status:** Accepted
- **Scope:** Product language, generated AI content, export templates, app naming, documentation
- **Replaces:** The Chinese display/executable/module names in [DEC-20260905-002](#dec-20260905-002) and Chinese title output in [DEC-20260904-002](#dec-20260904-002). Bundle identity and independent title generation remain unchanged.

### Context and decision

The user requested English for all Chinese text in the app and documentation. UI copy alone would leave permission descriptions, status/errors, export metadata, prompts, and generated insights/titles in Chinese.

- Use SameWave for the display name, executable, Swift module, and desktop app. Declare English as the app's development/supported localization. Keep bundle ID `com.plus.samewave`, storage namespaces, signing identity, and persisted language-pair values.
- Translate all app-owned copy, accessibility text, permission descriptions, prompts, Schema descriptions, and export templates to English. Use English Gregorian dates and English duration/count formatting.
- Request English insights and titles. Titles use 3–8 words with a 60-character cap, replacing the Chinese-oriented length bound. Refinement follows the selected source/target pair; original transcripts, translations, vocabulary spellings, and existing saved AI content are not rewritten.
- Translate all Markdown documentation and rename Chinese document filenames, updating local links and stable decision anchors. Preserve historical dates, evidence, and superseded decisions.
- Accommodate longer English labels with a wrapping control dock and compact history/insight actions carrying full tooltips and accessibility labels. Retain reproducible minimum-size UI snapshots and an English-copy/link audit.

### Rejected alternatives and tradeoffs

- **Translate only visible SwiftUI strings:** leaves generated artifacts, errors, and AI output inconsistent.
- **Add a language switch and parallel Chinese resources:** outside the request and introduces an obsolete second copy path.
- **Translate stored meeting content or force meeting languages to English:** would alter user data and the meeting's chosen translation direction.
- **Rename the bundle/storage identity again:** unnecessary for English presentation and would split settings, keys, permissions, and data.
- English text needs more room; narrow history titles may truncate with complete text available in tooltips. Model prompts request English output, while the model remains responsible for actual content.

### Validation and files

- XcodeGen and unsigned Debug build passed. Full XCTest: 106/106 on `SameWave`, `platform=macOS,arch=arm64`. Tests cover identity/localization, English prompt contracts, all four language-pair exports/refinement prompts, history metadata, and preserved transcript content.
- Rendered and inspected built-in/custom AI settings, vocabulary settings/review, and new/history meetings at 940×480. The initial screenshots exposed compressed capture controls and wrapped headers; corrected layouts were rendered and inspected again.
- English-copy/local-link audit passed. All 27 previous decision IDs remain; plist changes are limited to English identity/localization/copy and entitlements are unchanged.
- Ran `./build.sh` with the existing certificate, replaced and launched `~/Desktop/SameWave.app`, and verified its strict signature and desktop process. The previous desktop bundle was renamed during this delivery, with no legacy install path in the script.
- No live audio, system permission interaction, Apple Translation, or external AI generation was exercised. Existing `TrafficLightConfigurator` concurrency warnings remain outside this change.
- Files: `Sources/`, `Tests/`, `project.yml`, `build.sh`, `scripts/check_english.py`, README, AGENTS, MEMORY, and `doc/`.

---

<a id="dec-20260905-005"></a>
## DEC-20260905-005: Install and launch the desktop app after development by default

- **Date:** 2026-09-05
- **Status:** Accepted
- **Scope:** Development delivery workflow and continuing authorization
- **Context:** Completing only build/tests required the user to separately request desktop installation and launch. The user explicitly asked to make these the default final steps.
- **Decision:** Save the preference in `MEMORY.md`, which `AGENTS.md` requires reading at task start. After development and required validation, run `./build.sh`, then verify signature and desktop process without repeated confirmation. Follow explicit task-specific exceptions.
- **Rejected alternatives:** Keeping authorization only in the current conversation or asking on every task would not ensure consistent future delivery.
- **Rationale/tradeoffs:** Reuse the existing script/signature so the user can experience the result immediately. Replacing and restarting the desktop app is explicitly authorized.
- **Validation/impact:** The preceding task successfully ran the script and verified signature/process. This decision changed only memory and documentation, not the app or script. Development/collaboration guides removed the default no-install constraint.
- **Files:** `MEMORY.md`, `AGENTS.md`, `doc/06-development-and-validation.md`, `build.sh`.

---

<a id="dec-20260905-004"></a>
## DEC-20260905-004: Restore the last selection instead of selecting the newest unfinished meeting

- **Date:** 2026-09-05
- **Status:** Accepted
- **Scope:** Main-window selection, startup recovery, session switching

### Context and decision

History selection previously lived only in `MainView` memory, while startup mounted the newest unfinished record. Reopening the last viewed conversation requires separating recovery from selection.

- Persist the displayed meeting UUID in UserDefaults `selectedMeetingID`; remove it for a new meeting. SwiftData still owns history/transcripts.
- The coordinator updates selection with lifecycle state; Views bind to it. History selection takes precedence over a mounted background session. Update selection only after successful switch/end/delete; preserve it on failure.
- At startup, normalize unfinished records to paused, then restore the selection. Ended records show history; unfinished records mount paused. Missing, invalid, or deleted selections show a new meeting. Database errors retain the key and show an error.

### Rejected alternatives and tradeoffs

- **Keep prioritizing the newest unfinished record:** overrides the user's history/new-meeting intent. Other paused records remain manually selectable.
- **Save only on exit or View refresh:** misses window closure, mounted-session switches, and abnormal termination. Save immediately on selection/mount changes.
- Persist only a stable UUID, without SwiftData objects, duplicate content, new database fields, or compatibility paths.

### Validation and impact

- XcodeGen and unsigned Debug passed; generated plist/entitlements unchanged. Full XCTest: 100/100, `SameWave`, `platform=macOS,arch=arm64`.
- Ten new tests cover rebuilt-coordinator history/paused recovery, invalid/deleted records, new meetings, consecutive mounts, history priority, deletion, and ending, using isolated UserDefaults and in-memory SwiftData without audio/translation.
- Ran `build.sh` with the existing certificate, replaced/launched the desktop app, and verified strict signature/process. Native UI automation was unavailable; actual reopen consistency across sidebar/stage/insights still required signed-app manual acceptance.
- Files: `Sources/Meeting/CaptureCoordinator.swift`, `Sources/History/MeetingHistory.swift`, `Sources/App/MainView.swift`, `Sources/App/MeetingSidebar.swift`, `Sources/App/MeetingStage.swift`, `Sources/App/SameWaveApp.swift`, `Tests/MeetingSelectionTests.swift`, README, architecture/session/validation references.

---

<a id="dec-20260905-003"></a>
## DEC-20260905-003: Share AI configuration across the app, with insights as a consumer

- **Date:** 2026-09-05
- **Status:** Accepted
- **Scope:** Settings architecture, AI configuration ownership, feature availability

### Context and decision

Insights, refinement, titles, and Markdown vocabulary already shared provider settings, but the page was named after insights and refinement checked availability through the insight engine. Shared infrastructure appeared subordinate to one feature.

- Name the settings entry AI Services and identify all four consumers. Keep insights as a distinct feature that asks for AI configuration.
- `AppDelegate` owns one `AISettings`; use cases create providers directly from it. UI reads shared configuration rather than routing other features' availability through `InsightEngine`.
- Move shared configuration, `LLMProvider`, HTTP, strict JSON decoding, and AI settings UI to `Sources/AI/`; settings navigation/container stays in `Sources/App/`. Remove insight-specific configuration types/paths.
- Configuration actions select the AI tab before opening Settings, without committing vocabulary drafts. Save remains explicit; connection tests use drafts. Insight content triggers remain unchanged.

### Rejected alternatives and tradeoffs

- **Rename only the tab:** leaves refinement dependent on the insight engine and invites further misuse.
- **Separate provider settings per feature or add a global enable switch:** no current need for multiple providers or another switch.
- **Rename persisted keys and require reconfiguration:** meanings/data structures are unchanged, so retain the same sole UserDefaults/Keychain storage without dual reads or migrations.
- Local captions, translation, manual vocabulary, history, and export remain independent of AI. Scheduling, persistence, and sent-data boundaries are unchanged.

### Validation and impact

- XcodeGen and unsigned Debug passed; full XCTest 90/90 on `SameWave`, `platform=macOS,arch=arm64`; generated plist/entitlements unchanged.
- Tests cover key/URL/model validation, four unconfigured consumers, editable local vocabulary, navigation/draft preservation, and rendered screenshots of built-in/custom AI settings and vocabulary.
- Validation exposed non-HTTP protocols incorrectly normalized as HTTPS hosts; fixed at the resolver boundary with an endpoint regression.
- Subsequently ran `build.sh`, signed with the existing certificate, installed/launched, and verified signature/process. No real AI calls; connection testing, Keychain writes, and full Settings interaction still required manual smoke tests. Existing window-button concurrency warnings were outside scope.
- Files: `Sources/AI/`, `Sources/App/SettingsView.swift`, `Sources/App/SameWaveApp.swift`, `Sources/App/InsightInspector.swift`, `Sources/App/MeetingStage.swift`, `Sources/Capture/SpeechVocabularySettingsView.swift`, `Tests/AISettingsTests.swift`, `Tests/OpenAIEndpointResolverTests.swift`, README and AI/architecture/validation references.

---

<a id="dec-20260905-002"></a>
## DEC-20260905-002: Use a unified SameWave app identity

- **Date:** 2026-09-05
- **Status:** Superseded
- **Superseded by:** [DEC-20260905-006](#dec-20260905-006) replaces the Chinese display/executable/module and installation names. The bundle identity and storage decisions remain valid.
- **Scope:** App identity, settings/secrets namespaces, speech-model cache, project entry points

### Context and decision

The official English name became SameWave, with old names removed and no compatibility/migration paths. Project, target, scheme, entry type, and filenames use it; bundle IDs became `com.plus.samewave` and `com.plus.samewave.tests`. Model identifiers and support directories follow the same naming. At adoption, the display name, executable, and Swift module retained the Chinese product name.

### Rejected alternatives and tradeoffs

- **Rename presentation only, retaining the old runtime identity:** preserves settings but leaves a second permanent naming system.
- **Migrate or dual-read old settings, keys, and caches:** adds transitional state and compatibility paths.
- New UserDefaults, Keychain service, and model caches are separate from the old identity. Users must reconfigure settings/vocabulary/keys and may need permissions again. Existing files are not deleted; SwiftData history models/storage remain unchanged.
- The installer retained the personal certificate and then-Chinese desktop path. Build failure must exit before signing/installing stale artifacts.

### Validation and impact

- XcodeGen, unsigned Debug, and `bash -n build.sh` passed; full XCTest 83/83 on `SameWave`, `platform=macOS,arch=arm64`, including bundle identity assertions.
- The signed desktop app with the new identity was not installed/launched in this task. Old-data reuse, authorization, and real audio were not validated by unit tests.
- Permission investigation confirmed that XCTest still runs startup speech/microphone authorization; temporary and installed signatures under one bundle ID can conflict in TCC. System logs confirmed this. Renaming did not change startup permissions or reset authorization.
- Files: `project.yml`, `build.sh`, `Sources/App/SameWaveApp.swift`, `Sources/Resources/SameWave.entitlements`, `Sources/Capture/CustomSpeechLanguageModel.swift`, `Sources/AI/AISettings.swift`, `Tests/AppIdentityTests.swift`, README and development reference.

---

<a id="dec-20260905-001"></a>
## DEC-20260905-001: Review Markdown vocabulary incrementally, retain results, and save selected terms

- **Date:** 2026-09-05
- **Status:** Accepted
- **Scope:** Vocabulary import/review, cancellation/retry, persistence, diagnostics
- **Replaces:** Stop-clears-results in [016](#dec-20260904-016), and return-to-Settings-to-save in [014](#dec-20260904-014), [010](#dec-20260904-010), and [008](#dec-20260904-008). File-picker order, separate window, close-to-cancel, and serial budgets remain.

### Context

Review previously waited for all serial requests. Stop lost successes, failure required reselecting everything, plain-text review conflated editing/selection, and returning to Settings to save could submit unrelated manual edits. Hidden retries also obscured time spent.

### Decision and invariants

- Append deduplicated candidates after each success, selected by default, with editing, Select All/Deselect All, and expandable local excerpts. Stable IDs, original extraction identity, and a seen set prevent later results from resetting edits/selections or resurrecting candidates.
- Stop cancels current/pending requests while retaining successes; no candidates returns to selection. Retry only failed, interrupted, and unsent requests, never successful ones. Keep the operation's provider configuration fixed; each retry run permits an initial attempt plus two retries.
- Closing generation cancels and discards unsaved state without affecting saved vocabulary. Observe actual NSWindow closure, not View state, hiding, or Settings closure. Tokens reject late results; new runs await old cancellation to remain serial.
- Add and Save persists only selected new terms, deduplicating against saved vocabulary, manual draft, and other candidates. Add new terms to the draft while preserving other edits/formatting. Cancelling Settings does not undo saved imports. Generation can continue during saving; feedback stays inline.
- Derive filenames/excerpts locally; do not send them as new AI fields. Explicitly flag spellings absent from source. Content, candidates, sources, and timing stay in this window's memory.
- Record monotonic per-attempt duration and success/error/stop in collapsed details. Measure provider invocation through response validation, excluding retry delays. Do not present combined duration as inference time or change models/reasoning/concurrency based on guesses.

### Rejected alternatives and tradeoffs

- **Review only after all requests / clear on stop:** delays first value and wastes successes.
- **Parallelize for speed:** the user explicitly required serial requests, with no evidence separating server latency.
- **Save the entire Settings draft:** submits unconfirmed manual changes.
- **Persist an import queue for restart recovery:** beyond the separate-window workflow; closing explicitly abandons unsaved progress.
- Partial results may not cover all documents. Preserve incomplete states/errors and explicit retry instead of claiming full success.

### Validation and impact

- XcodeGen and unsigned Debug passed; full XCTest 81/81 on `SameWave`, `platform=macOS,arch=arm64`.
- Coverage includes incremental results, Unicode fragmentation, two retries then continuation, stop/late responses, incomplete-only retries, edits/selections, omitted provenance, selective persistence, save deduplication. Native NSWindow tests prove hide retains and close clears; review screenshots retained.
- An initial test process exited early with code 0; isolated import tests and a full rerun subsequently passed. No business-code or service-latency cause was inferred. No real AI calls; actual model timing and file-picker interaction remained for signed-app verification.
- Files: `Sources/Capture/VocabularyImportController.swift`, `Sources/Capture/VocabularyImportWindow.swift`, `Sources/Capture/SpeechVocabularySettings.swift`, `Sources/Insights/VocabularyGenerator.swift`, corresponding XCTest, README and architecture/vocabulary/AI references.

---

<a id="dec-20260904-016"></a>
## DEC-20260904-016: Closing generation cancels; Stop keeps the window open

- **Date:** 2026-09-04
- **Status:** Superseded
- **Superseded by:** [DEC-20260905-001](#dec-20260905-001) replaces stop-clears-results. Close cancellation, Stop keeping the window, and UI simplification remain.
- **Scope:** Vocabulary generation, window closure, explicit stopping
- **Replaces:** [014](#dec-20260904-014)'s background continuation after closing generation. Settings independence, initial selection order, review, and explicit saving remain.

### Context

Closing the window while AI continued invisibly made task state and continuing cost unclear. Stop should end the current run while leaving the tool available for another operation.

### Decision

- Closing generation immediately cancels in-flight requests, invalidates the token, clears unconfirmed review text, and resets the Controller. Reopening does not restore the closed operation.
- Stop performs the same cancellation/cleanup but leaves the window open at file selection.
- Switching/closing Settings still leaves the separate window's app-owned task intact.
- Remove initial rule cards for file size, request characters, and retry counts; retain constraints in documentation and specific errors.

### Rejected alternatives

- **Continue after window closure:** invisible activity/cost conflicts with ending the visible workflow.
- **Close on Stop:** adds needless reentry when changing files.
- **Cancel only networking but retain review:** reopening would restore candidates the user believed abandoned.

### Rationale and tradeoffs

Window closure ends the workflow; Stop ends a run while keeping the tool open. Accidental closure loses unconfirmed candidates, but previously confirmed app-owned vocabulary drafts remain.

### Impact

- `VocabularyImportWindow` called stop/cleanup on disappearance, with progress copy explaining close cancellation.
- Stop resets the Controller without calling a window-close API.
- README and vocabulary/AI references distinguish Settings closure, generation closure, and Stop.

### Validation and files

- XCTest verified stop resets Controller/review; XcodeGen and unsigned Debug passed; macOS arm64 tests 68/68.
- `Sources/Capture/VocabularyImportWindow.swift`, `Tests/SpeechVocabularySettingsTests.swift`, README, pipeline and AI references.

---

<a id="dec-20260904-015"></a>
## DEC-20260904-015: Choose initial Markdown files before opening generation

- **Date:** 2026-09-04
- **Status:** Accepted
- **Scope:** First file selection and window presentation order
- **Replaces:** [014](#dec-20260904-014)'s window-first flow. App-owned state, separate progress/review, Settings independence, and explicit saving remain.

### Context

Opening an empty window before the picker added a transition without useful information. Generate from Markdown expresses an intent to choose input; persistent progress/review is useful only after selection starts work.

### Decision

- The settings button opens the native picker directly, without creating generation first.
- Selection goes to the app-owned `VocabularyImportController`, then opens the window for reading, requests, errors, and review. Cancelling initial selection creates no task/window.
- Existing reading/generation/review work reopens its window without another picker, avoiding replacement of active state.
- Subsequent Continue Choosing/Choose Again actions remain within that window; the initial two-stage entry is unchanged.

### Rejected alternatives

- **Always open an empty window first:** unnecessary transition and leftover window on cancellation.
- **Show progress in Settings after selection:** reintroduces Scene-lifetime coupling.
- **Show a new picker during active work:** risks overwriting/cancelling paid work.

### Rationale and tradeoffs

Input selection precedes processing naturally. Create a persistent window only when work exists. App-owned tasks/drafts preserve continuation and review across Settings closure.

### Impact

- `SpeechVocabularySettingsView` owns only the initial picker's UI state and requests the generation window after selection.
- `handleFileSelection` explicitly returns whether to present it: false for cancellation, true for other success/error states.
- README, architecture, pipeline, and AI references distinguish initial selection from separate progress/review.

### Validation and files

- XCTest verifies cancelling initial selection starts nothing and requests no second window; XcodeGen/unsigned Debug passed; macOS arm64 67/67.
- `Sources/Capture/SpeechVocabularySettingsView.swift`, `Sources/Capture/VocabularyImportWindow.swift`, `Tests/SpeechVocabularySettingsTests.swift`, README, architecture/pipeline/AI references.

---

<a id="dec-20260904-014"></a>
## DEC-20260904-014: Give Markdown generation a separate window and app-owned state

- **Date:** 2026-09-04
- **Status:** Superseded
- **Superseded by:** [015](#dec-20260904-015) changes initial picker order; [016](#dec-20260904-016) changes continuation after closure; [DEC-20260905-001](#dec-20260905-001) changes saving. App-owned state, independent progress/review, and Settings independence remain.
- **Scope:** Generation, window lifetime, unsaved drafts, cancellation
- **Replaces:** [010](#dec-20260904-010)'s Settings-owned task and review sheet. Deduplication, partial success, and explicit saving remain.

### Context

Generation crowded vocabulary settings with instructions, selection, progress, and result state, then used a sheet for review. Settings tab/window destruction could destroy long-running request/review state.

### Decision

- Settings retains a short explanation and Generate from Markdown. A separate SwiftUI `Window` Scene owns selection, reading, serial progress, Stop, failures, editing, and confirmation.
- App assembly owns `VocabularyImportController`. At adoption, switching/closing Settings or temporarily closing generation did not cancel or clear review; reopening restored state. Only explicit Stop or app exit ended active requests.
- App assembly also owns shared `SpeechVocabularyDraft`. Confirmation added deduplicated terms to an app-lifetime unsaved draft, preserved across Settings closure but not persisted until Save in Vocabulary.
- Generation closure did not mean cancelling review. Cancel Without Adding abandoned candidates without changing the existing draft.

### Rejected alternatives

- **Keep the task in Settings, move only review:** Settings closure would still cancel reading/generation.
- **Cancel on generation closure:** then conflicted with the requirement to continue in the background and reopen review.
- **Save immediately on review confirmation:** conflates accepting candidates with applying all vocabulary edits.
- **Persist unsaved drafts:** restart recovery adds unnecessary lifecycle/conflict semantics.

### Rationale and tradeoffs

The separate window gives long work a clear presentation boundary; app-owned state is independent of window existence. Final Save keeps unconfirmed configuration out of ASR/insights. At adoption, closing could leave paid requests running, requiring explicit disclosure and Stop.

### Impact

- `AppDelegate` constructs/injects draft and Controller into Settings/generation.
- Vocabulary Settings no longer owns import tasks or a review sheet; remove `VocabularyReviewSheet` and integrate review into the window.
- Documentation describes window separation, Settings lifetime, background continuation, and explicit final Save.

### Validation and files

- XCTest confirms adding terms to the app-owned draft does not change saved vocabulary until Save; XcodeGen/unsigned Debug passed; macOS arm64 66/66.
- `Sources/App/SameWaveApp.swift`, `Sources/Capture/VocabularyImportWindow.swift`, `Sources/Capture/SpeechVocabularySettings.swift`, `Sources/Capture/SpeechVocabularySettingsView.swift`, `Tests/SpeechVocabularySettingsTests.swift`, README and architecture/pipeline/AI references.

---

<a id="dec-20260904-013"></a>
## DEC-20260904-013: Limit Markdown to 3 MB per file and 30 MB per selection

- **Date:** 2026-09-04
- **Status:** Accepted
- **Scope:** Vocabulary generation, file reading, resource limits
- **Replaces:** The combined 3 MB selection limit in [009](#dec-20260904-009), [011](#dec-20260904-011), and [012](#dec-20260904-012). Serial 20,000-character requests, retries, partial success, and review remain.

### Context

A 3 MB cap across all selected files constrained useful multi-file input. Bounded serial requests already protect individual AI calls; local per-file reading and total-operation resources/cost need separate limits.

### Decision

- Each UTF-8 `.md`/`.markdown` file permits 3,000,000 bytes; all deduplicated selected files permit 30,000,000 bytes. Display distinct per-file and total-selection errors.
- Validate metadata before reading, then validate actual `Data.count` afterward rather than assuming metadata is present/accurate.
- Add no total character cap. Keep 18,000-character fragments, 20,000-character requests, serial work, two retries, and partial success.

### Rejected alternatives

- **Only raise the total to 30 MB:** fails the explicit per-file requirement and allows large single reads.
- **3 MB each without a total:** leaves operation memory/time/request count/cost unbounded.
- **Character limits only:** Swift character counts do not accurately bound UTF-8 bytes.

### Rationale and tradeoffs

Two byte limits manage local and operation-wide resources while allowing useful project sets above 3 MB. Near-30 MB selections may need many serial requests and significant time/cost; progress and Stop remain available.

### Impact

- `VocabularyDocumentLoader` has separate constants/errors; settings originally displayed both limits.
- README and pipeline/AI references disclose both limits.

### Validation and files

- XCTest covers multi-file input above 3 MB, rejection above 3 MB per file, exact total 30 MB and overflow. XcodeGen/unsigned Debug passed; macOS arm64 65/65.
- `Sources/Insights/VocabularyGenerator.swift`, `Sources/Capture/SpeechVocabularySettingsView.swift`, `Tests/VocabularyGeneratorTests.swift`, README and pipeline/AI references.

---

<a id="dec-20260904-012"></a>
## DEC-20260904-012: Use 20,000-character vocabulary requests and tolerate individual failures

- **Date:** 2026-09-04
- **Status:** Superseded
- **Superseded by:** [013](#dec-20260904-013) replaces the combined 3 MB reading limit. Request budget, serial work, retries, partial success, review, and explicit saving remain.
- **Scope:** AI input budget, retries, partial failure
- **Replaces:** [011](#dec-20260904-011)'s 400,000 characters, 500 candidates, and 180-second timeout; all-or-nothing success in [008](#dec-20260904-008), [009](#dec-20260904-009), and [010](#dec-20260904-010). The then-current 3 MB selection cap, serial execution, review, and saving remained.

### Context

400,000-character requests were aggressive across tokenizers/gateways; timeouts/context failures forced large retries. Independent extraction failures should not discard other validated results, but incomplete coverage must be visible.

### Decision

- Select multiple UTF-8 Markdown files with the then-current 3 MB combined byte cap and no additional total character cap.
- Split locally into at most 18,000 Swift-character fragments, add document locators, and pack Markdown bodies up to 20,000 characters per actual AI call. Fragments are not requests; prompts, request instructions, Schema, and output are outside this body budget.
- Process in document/fragment order, strictly serial. Each request gets an initial attempt plus two retries, waiting 500 ms then 1,000 ms. Cancellation stops immediately without retry/partial-success handling.
- After three failures, record request number/error and continue. Deduplicate successes against the draft for independent review, showing failed request numbers. Only all-request failure fails the operation.
- Restore at most 50 candidates per success and a 30-second provider timeout. Candidates must pass named-entity and recognition-value gates.

### Rejected alternatives

- **Concurrent requests:** burst rate limits and less predictable ordering/Stop/progress.
- **Keep 400,000 characters:** fewer calls but greater tokenizer/gateway/network dependence and retry cost.
- **Fail everything on any failure:** discards validated results and compounds failure probability with file count.
- **Silently skip failures:** falsely implies full document coverage.

### Rationale and tradeoffs

20,000 characters reduces context/timeout risk without provider tokenizers. Serial bounded retries make load/worst-case time predictable. Partial success preserves value while explicit failures prevent false completeness. Near-3 MB input then required more serial calls, time, and cost.

### Impact

- Generator returns candidates, success count, and failure details. Partial success reaches review; only all-failed input shows an operation error.
- Documentation distinguishes actual requests from internal fragments and discloses retry, partial success, cost, and off-device text.

### Validation and files

- XCTest covers 20,000/18,000 boundaries, lossless long-paragraph splitting, two retries, success on the third attempt, continuation after failure, partial output, and progress. XcodeGen/unsigned Debug passed; macOS arm64 63/63.
- `Sources/Insights/VocabularyGenerator.swift`, `Sources/Capture/SpeechVocabularySettingsView.swift`, removed `Sources/Capture/VocabularyReviewSheet.swift`, `Sources/AI/OpenAICompatibleProvider.swift`, `Tests/VocabularyGeneratorTests.swift`, README and pipeline/AI references.

---

<a id="dec-20260904-011"></a>
## DEC-20260904-011: Expand vocabulary batches toward 100K English tokens

- **Date:** 2026-09-04
- **Status:** Superseded
- **Superseded by:** [012](#dec-20260904-012) replaces 400,000 characters, 500 candidates, 180 seconds, and atomic success; [013](#dec-20260904-013) replaces the total 3 MB cap. Serial work, progress, and review remain.
- **Scope:** AI input budgets and model capability boundaries
- **Replaces:** [009](#dec-20260904-009)'s 6,000-character batch budget. The then-current total byte cap, serial work, progress, and atomic submission remained.

### Context

6,000 English Markdown characters are roughly 1,500–2,000 tokens, producing many requests near 3 MB. The user chose approximately 100K tokens per batch for configured large-context AI to reduce calls.

### Decision

- Estimate four English characters/token: 400,000 Swift characters per body, roughly 100K input tokens; use 390,000-character fragments to leave room for labels/separators.
- Raise Schema output from 50 to 500 candidates, avoiding artificial loss in long documents. The prompt says the maximum is not a quota. Raise completion timeout from 30 to 180 seconds for large input/output; keep Stop.
- Retain serial requests, the 3 MB combined input cap, progress, and no partial submission on any batch failure.
- This is approximate token budgeting, not model-context configuration. The model/service must fit body, system/user prompts, Schema, and output. Chinese, code, and tokenizer differences can make 400,000 characters far exceed 100K tokens and fail.

### Rejected alternatives

- **One provider tokenizer:** misleading precision across custom/multiple providers plus a new dependency.
- **Infer context from `/models`:** no uniform trustworthy context field.
- **100,000 characters:** approximately 25K English tokens, short of the user's target.

### Rationale and tradeoffs

A fixed bound approaches the requested English scale without provider branches and reduces calls. Non-English/code input can diverge greatly; smaller models fail explicitly. Review/atomic submission prevent incomplete drafts.

### Impact

- Expand generator batch/fragment/candidate limits; tests derive inputs from constants rather than old 6,000 values. Completion requests use 180 seconds; model discovery retains a short timeout.
- References describe the estimate and context risk; insight/title 6,000-character budgets stay unchanged.

### Validation and files

- XCTest covers 400,000-character limits, progress, lossless long-paragraph splitting, and atomicity after later failures. XcodeGen/unsigned Debug passed; macOS arm64 62/62.
- `Sources/Insights/VocabularyGenerator.swift`, `Tests/VocabularyGeneratorTests.swift`, pipeline and AI references.

---

<a id="dec-20260904-010"></a>
## DEC-20260904-010: Review AI-generated terms in a separate window first

- **Date:** 2026-09-04
- **Status:** Superseded
- **Superseded by:** [012](#dec-20260904-012) removes the all-batches-success prerequisite; [014](#dec-20260904-014) replaces Settings-owned work/review sheet; [DEC-20260905-001](#dec-20260905-001) changes saving. Deduplicated review and explicit saving remain.
- **Scope:** Vocabulary generation, candidate review, draft mutation
- **Replaces:** [008](#dec-20260904-008)'s direct append into the draft after all batches succeed. Other strict Schema, atomic generation, saving, and disclosure decisions then remained.

### Context

Generated terms previously mixed directly into the editor after all batches succeeded. Although Save was still required, users could not easily identify or review new terms separately from existing vocabulary.

### Decision

- After all batches succeed, normalize/deduplicate and exclude terms already in the current draft, without changing the editor yet.
- If new terms exist, open a separate review window containing only those candidates. Users may edit/delete lines; Add to Vocabulary Draft explicitly merges them.
- Cancel/close adds nothing. Confirmed terms remain unsaved until Save in Vocabulary, before local recognition or later AI uses them.
- Empty extraction or all-existing results show status without an empty review window.

### Rejected alternatives

- **Highlight new lines in the main editor:** TextEditor cannot reliably maintain per-line provenance styles, and generation would interact with concurrent manual edits.
- **Save generated terms immediately:** bypasses review and explicit-save semantics.
- **Read-only results:** forces users back to the main editor to find/fix terms, preventing effective review.

### Rationale and tradeoffs

Separate review establishes a clear boundary for deletion/correction before merging. Two confirmations express different intentions: reviewing candidates and saving vocabulary. The extra step provides control over AI-generated configuration.

### Impact

- `SpeechVocabularySettingsView` creates a review request instead of modifying the draft directly.
- `VocabularyReviewSheet` owns editing/confirmation; `VocabularyCandidateReview` excludes existing draft terms.
- README and references describe review and cancellation without draft mutation.

### Validation and files

- XCTest covers case-insensitive deduplication against the draft; XcodeGen/unsigned Debug passed; macOS arm64 60/60.
- `Sources/Capture/SpeechVocabularySettingsView.swift`, removed `Sources/Capture/VocabularyReviewSheet.swift`, `Sources/Insights/VocabularyGenerator.swift`, `Tests/VocabularyGeneratorTests.swift`, README and pipeline/AI references.

---

<a id="dec-20260904-009"></a>
## DEC-20260904-009: Read up to 3 MB of Markdown and generate serial batches

- **Date:** 2026-09-04
- **Status:** Superseded
- **Superseded by:** [011](#dec-20260904-011) first changes the 6,000-character budget; [012](#dec-20260904-012) changes requests/retries/atomicity; [013](#dec-20260904-013) changes 3 MB total to 3 MB per file and 30 MB total. Serial execution and progress remain.
- **Scope:** Reading limits, AI batches, progress
- **Replaces:** [008](#dec-20260904-008)'s 60,000-character body cap and 1 MB reading cap. Draft review, strict Schema, atomic submission, and disclosure then remained.

### Context

With bounded serial AI batches, a total body-character cap does not protect individual model contexts and rejects otherwise processable documents. A 1 MB multi-file cap was also restrictive. Long serial work needs visible progress to avoid appearing stuck.

### Decision

- Remove the 60,000-character total cap. Limit a multi-file selection to 3,000,000 raw bytes, still requiring UTF-8 `.md`/`.markdown`.
- Split/pack locally into batches of at most 6,000 characters and call the current `InsightProvider` sequentially. This provider-independent application budget does not set the model's context window; the selected model/server owns that capability.
- Show reading state and completed/total batches. Preserve stop/failure semantics: append no partial results on any failure/cancellation; only complete success merges deduplicated candidates into the reviewable draft.

### Rejected alternatives

- **Raise a character total instead:** does not reliably represent UTF-8 bytes and retains an unnecessary second total boundary.
- **Adapt to advertised model context:** custom metadata/limits are unreliable and create inconsistent provider costs/failure modes.
- **Send all batches concurrently:** creates burst limits and less predictable cancellation/errors; this use case does not require concurrency for latency.
- **Remove every total limit:** local reading and serial requests still need resource/cost bounds.

### Rationale and tradeoffs

The 3 MB total bounds local reading/operation cost; 6,000 characters separately bounds each request. Serial work reduces rate-limit risk and keeps atomic submission simple; progress makes long work visible. Near-limit input takes more time/calls, with observable progress and Stop.

### Impact

- Loader validates extension, UTF-8, and total bytes without rejecting total character count.
- Generator retains 6,000-character serial batches and reports progress.
- Settings, README, and references disclose byte limits, batches, third-party sending, and model context boundaries.

### Validation and files

- XCTest covers reading beyond 60,000 characters, rejection above 3 MB, serial progress, batching, and atomic failure. XcodeGen/unsigned Debug passed; macOS arm64 59/59.
- `Sources/Insights/VocabularyGenerator.swift`, `Sources/Capture/SpeechVocabularySettingsView.swift`, `Tests/VocabularyGeneratorTests.swift`, README and pipeline/AI references.

---

<a id="dec-20260904-008"></a>
## DEC-20260904-008: Extract Markdown vocabulary into a reviewable draft

- **Date:** 2026-09-04
- **Status:** Superseded
- **Superseded by:** [009](#dec-20260904-009) changes character/byte limits; [010](#dec-20260904-010) changes direct draft append; [012](#dec-20260904-012) replaces atomic all-or-nothing generation; [DEC-20260905-001](#dec-20260905-001) changes saving. Strict Schema and disclosure remain.
- **Scope:** Vocabulary generation, AI data boundaries, confirmation, batch failures

### Context

English vocabulary required manual editing despite project documents/agendas already containing names and terms. Existing providers supported strict Schema, but Markdown may contain sensitive information or prompt injection, and extracted terms are not confirmed user settings.

### Decision

- With complete AI configuration, allow explicit selection of one or more UTF-8 `.md`/`.markdown` files, originally capped at 60,000 body characters and 1 MB reading.
- Read locally without uploading file objects/filenames or persisting content. Pack paragraphs into serial 6,000-character batches for `InsightProvider`; each strict Schema returns at most 50 single-line terms of at most 100 characters.
- Treat documents as untrusted data. Ignore embedded instructions and extract names/acronyms/uncommon terms likely spoken in English meetings where spelling matters. Exclude ordinary words, URLs, paths, and pure Markdown/code syntax.
- Require every batch to succeed before normalizing/deduplicating and appending to the draft. Do not overwrite or autosave it. Users review and Save before terms enter ASR/insights/refinement.
- Stop, invalid files, oversized content, network failure, or any schema violation cancels/fails the operation without partial draft writes.

### Rejected alternatives

- **Regex/Markdown heuristics:** cannot reliably distinguish ordinary words, code identifiers, and relevant spoken names.
- **Replace/save vocabulary directly from AI:** over-extraction/misclassification bypasses confirmation of recognition bias and future third-party disclosure.
- **One unbounded request:** cannot fit small contexts and makes failure cost/truncation unpredictable.
- **Provider-specific file-upload APIs:** breaks the single OpenAI-compatible boundary and adds remote-file lifecycle/privacy management.

### Rationale and tradeoffs

Reuse provider/Schema for an end-to-end workflow without dependencies or duplicate configuration. Draft-only output preserves explicit activation; atomic submission avoids apparently complete but partial vocabulary. Long documents require serial calls without global cross-batch ranking; local deduplication and review suffice for current needs.

### Impact

- Generator owns reading limits, batching, prompt, Schema validation, normalization. The View owns selection, task state, draft merge.
- Markdown content is a new explicit third-party disclosure surface, documented in settings/README/AI references.
- Saved terms keep existing activation: next English start/resume for Speech, full saved vocabulary for refinement, context matches for insights.

### Validation and files

- XCTest covers structured deduplication, multiline rejection, later-batch atomic failure, lossless long-paragraph splitting, multi-file reading, content limits, extension rejection. Unsigned Debug passed; macOS arm64 58/58.
- `Sources/Insights/VocabularyGenerator.swift`, `Sources/Capture/SpeechVocabularySettingsView.swift`, `Sources/Capture/SpeechVocabularySettings.swift`, `Sources/App/SettingsView.swift`, `Tests/VocabularyGeneratorTests.swift`, pipeline and AI references.

---

<a id="dec-20260904-007"></a>
## DEC-20260904-007: Prefer refined source for historical insights

- **Date:** 2026-09-04
- **Status:** Accepted
- **Scope:** Historical insight input, partial refinement, live insight/title factual sources

### Context

Refinement saves `refinedSource` with recognition, spelling, and punctuation corrections, but history insights still used only `sourceText`. This wasted saved improvements. Partial success also means not every line has refinement.

### Decision

- On historical generation/regeneration, assemble chronological input preferring nonempty `refinedSource` per line, otherwise `sourceText`.
- Never use `refinedTarget` as factual input, avoiding translation errors.
- Live insights keep live source. Titles keep original source to preserve parallel generation timing and stability.
- Do not delete/rerun cached insights automatically after refinement. Only explicit Regenerate uses current refined content.

### Rejected alternatives

- **Always use original history:** wastes corrections and terminology improvements.
- **Use refined translation:** introduces translation bias and inconsistent factual sources across language modes.
- **Revert the whole meeting if one refinement is missing:** discards successful batches' value.
- **Automatically invalidate/regenerate insights:** deletes saved results or incurs requests without confirmation.

### Rationale and tradeoffs

Per-line priority matches refinement display, using better text without requiring complete success. Explicit call-site semantics protect live/title behavior from accidental shared-helper changes. Cached insights can lag later refinement, preserving user control over external requests and replacement.

### Impact

- `flatten(lines:preferringRefinedSource:)` requires callers to choose semantics; history prefers refinement, titles use originals.
- Vocabulary matching uses assembled historical input, so corrected names can enter the prompt.

### Validation and files

- XCTest covers refined preference, blank per-line fallback, ordering, and original-source titles. Unsigned Debug passed; macOS 51/51.
- `Sources/App/InsightInspector.swift`, `Sources/Insights/InsightEngine.swift`, `Sources/Insights/MeetingTitleGenerator.swift`, `Tests/InsightEngineTests.swift`, `Tests/MeetingTitleGeneratorTests.swift`, AI reference.

---

<a id="dec-20260904-006"></a>
## DEC-20260904-006: Send only vocabulary matched in the current insight context

- **Date:** 2026-09-04
- **Status:** Accepted
- **Scope:** Insight prompts, vocabulary activation, third-party disclosure
- **Replaces:** [005](#dec-20260904-005)'s exclusion of vocabulary from live insights. Full refinement vocabulary and no title vocabulary remain.

### Context

Insights may misspell confirmed names/acronyms. Repeatedly sending the complete vocabulary would waste tokens and expose unrelated terms.

### Decision

- `InsightEngine` shares `SpeechVocabularySettings`. At each live/history request, match saved terms within the already bounded latest 6,000-character input and include only matches.
- Use case-insensitive literal search. Letter/digit term edges require nonalphanumeric boundaries; continue searching after rejected substring occurrences so an earlier false match cannot hide a later standalone term. Preserve configured order/spelling.
- Prompt only requires exact spelling when relevant and forbids inventing information to use vocabulary. No matches/list means no extra paragraph; Schema is unchanged.
- Refinement retains a full operation-wide snapshot; title requests include none.

### Rejected alternatives

- **Send the whole list each time:** repeatedly exposes unrelated project/personal names and uses context.
- **Simple case-insensitive substring search:** `PR` would match `project`.
- **Replace terms in output locally:** semantic correspondence is unreliable and can damage typed content.

### Rationale and tradeoffs

Deterministic filtering supplies relevant spellings with minimal added tokens/disclosure. It deliberately avoids fuzzy recovery of ASR sound-alikes, limiting exposure of sensitive terms absent from the actual conversation.

### Impact

- Inject shared vocabulary into coordinator, insight engine, and refiner.
- Saved edits affect the next insight request immediately; in-flight matches stay frozen.
- Settings/docs disclose different scopes for insights, refinement, and titles, including internal/personal names.

### Validation and files

- XCTest covers case-insensitive matches, boundaries, later standalone matches, order, empty-match prompts, and no forced insertion. Unsigned Debug passed; macOS 50/50.
- `Sources/Insights/InsightEngine.swift`, `Sources/App/SameWaveApp.swift`, `Sources/Capture/SpeechVocabularySettingsView.swift`, `Sources/App/SettingsView.swift`, `Tests/InsightEngineTests.swift`, architecture/pipeline/AI references.

---

<a id="dec-20260904-005"></a>
## DEC-20260904-005: Use user vocabulary in both local English ASR and AI refinement

- **Date:** 2026-09-04
- **Status:** Superseded
- **Superseded by:** [006](#dec-20260904-006) changes exclusion from live insights. Full refinement vocabulary, no title vocabulary, and other decisions remain.
- **Scope:** Vocabulary activation, refinement prompts, privacy disclosure
- **Replaces:** [DEC-20260903-003](#dec-20260903-003)'s complete vocabulary/cloud separation. Local recognition, explicit save, stage snapshots, and model caching remain.

### Context

User vocabulary originally affected only Apple Speech. First-time refinement lacked an AI glossary and could corrupt correctly recognized names; later `glossaryJSON` could not represent preconfirmed user spelling.

### Decision

- Refiner reads the same settings, freezing the saved list at operation start for every batch; mid-run edits do not affect it.
- Keep user vocabulary and previous AI glossary separate: vocabulary supplies candidate names/exact spelling only where context matches, without string replacement or invented target mappings. Existing AI target mappings take precedence.
- Preserve brands/products/people/acronyms without established translations. Empty vocabulary explicitly supplies no user terms.
- At adoption, send vocabulary only with explicit refinement, not live insights/titles. Disclose this cloud boundary; Apple training/model files remain local.

### Rejected alternatives

- **Map every term to itself:** wrongly prevents context-sensitive translation of words such as Wallet.
- **Deterministic output replacement:** cannot reliably infer semantic correspondence.
- **AI glossary alone:** first refinement lacks confirmed spellings and later runs may perpetuate errors.
- **Send vocabulary with all AI requests:** expands unnecessary disclosure for use cases not proofreading each word.

### Rationale and tradeoffs

One saved vocabulary shares user intent between ASR and cleanup without a second configuration. Conditional spelling hints can fix sound-alikes/capitalization without forcing translations or unrelated terms. Refinement now exposes additional vocabulary, requiring explicit UI/documentation disclosure.

### Impact

- Inject vocabulary into coordinator and refiner.
- Saved changes apply to the next refinement, but local ASR still waits for start/resume.
- Vocabulary may include internal/personal names; users should consider the chosen provider's data policy when enabling refinement.

### Validation and files

- XCTest covers populated/empty vocabulary prompts; unsigned Debug checks wiring and Swift 6 isolation.
- `Sources/Insights/TranscriptRefiner.swift`, `Sources/App/SameWaveApp.swift`, `Sources/Capture/SpeechVocabularySettingsView.swift`, `Sources/App/SettingsView.swift`, `Tests/TranscriptRefinerTests.swift`, pipeline/AI references.

---

<a id="dec-20260904-004"></a>
## DEC-20260904-004: Require strict JSON Schema for all AI structured outputs

- **Date:** 2026-09-04
- **Status:** Accepted
- **Scope:** Provider contracts, supported models, parsing failures, configuration
- **Replaces:** [001](#dec-20260904-001)'s assumption that any compatible model suffices and [DEC-20260903-002](#dec-20260903-002)'s tolerant parsing.

### Context

The provider sent `json_object` while prompts duplicated full examples. This guaranteed valid JSON, not keys/types/nesting. Clients extracted fences/surrounding prose and defaulted missing/wrong insight fields to empty values, risking false success. OpenAI, Qwen, and Kimi document strict `json_schema`, but compatibility alone does not prove support. Actual Cherry Studio Copilot testing accepted a complex Schema with HTTP 200 while returning an invalid top-level array, exposing a false positive in the simple connection test.

### Decision

- Each use case owns `LLMResponseSchema`: insights, cross-language refinement, same-language refinement, titles, and connection tests declare required/nullable fields and `additionalProperties: false`. Provider always sends the caller's Schema with `strict: true`.
- Prompts retain task/factual/style rules plus brief field semantics, without a full JSON example. This keeps one strict request path while reducing wrong structures from gateways that ignore Schema. Decode entire assistant content only; no fence/prose extraction or defaults for missing fields.
- Distinguish `finish_reason`, refusal, truncation, and HTTP 400 schema/parameter errors instead of generic parse errors.
- Limit built-ins to documented Qwen `qwen3.8-flash` and Kimi `kimi-k3`; remove DeepSeek, GLM, and JSON Object paths. Custom services use a representative nested-Schema connection test.
- Do not read saved API keys for removed provider IDs, preventing another provider's key being sent to Qwen after default selection. Require explicit reconfiguration.

### Rejected alternatives

- **Strict versus JSON Object by provider:** creates two reliability contracts for one feature.
- **Automatic fallback after strict failure:** hides capability/configuration errors and revives tolerant behavior.
- **Client-only JSON Object validation:** detects errors but still incurs unusable output/retry costs.
- **Full JSON Schema dependency:** current schemas need only a minimal encodable JSON value; server enforcement makes a new package unnecessary.

### Rationale and tradeoffs

Move structure from prompt advice into the API contract. Native support constrains generation; strict decoding gives failures clear meaning. Gateways can silently ignore Schema, so brief prompt semantics and client validation remain necessary. Small prompt duplication and occasional custom-gateway failures are accepted without provider branches or tolerant fallbacks.

### Impact

- Every new AI use case must supply a Schema, not merely an example prompt.
- Schema changes update Codable models, request-contract tests, and references together.
- Violations/truncation/refusal show actual failures rather than empty insights/defaulted fields.

### Validation and files

- XCTest covers strict request bodies, built-in models, prompt field semantics, `answer: null`, missing/wrong/excess fields, and rejected fences. The connection test uses nested objects/arrays. Actual Cherry Studio `copilot:gpt-5.5` returned a wrong top-level array with the old prompt and a decodable object after field semantics were added to the same strict request.
- `Sources/AI/LLMProvider.swift`, `Sources/AI/OpenAICompatibleProvider.swift`, `Sources/Insights/InsightModels.swift`, `Sources/Insights/InsightEngine.swift`, `Sources/Insights/TranscriptRefiner.swift`, `Sources/Insights/MeetingTitleGenerator.swift`, `Tests/OpenAICompatibleProviderTests.swift`, AI reference.

---

<a id="dec-20260904-003"></a>
## DEC-20260904-003: Do not regenerate a successfully saved title during refinement

- **Date:** 2026-09-04
- **Status:** Accepted
- **Scope:** Title lifecycle, AI cost, historical record stability
- **Replaces:** [002](#dec-20260904-002)'s title-regeneration trigger on every refinement

### Context

Ended transcripts are stable, and successful titles identify history. Regenerating on every refinement adds needless requests and can change familiar list titles.

### Decision

- Request a title alongside refinement only when `MeetingRecord` lacks a nonblank `aiTitle`.
- Once saved, Refine Again updates the transcript only, without requesting/replacing its title.
- Failed/empty titles retain the date display and remain eligible on the next refinement.
- Do not add a separate Regenerate Title action.

### Rejected alternatives

- **Regenerate every time:** extra cost and unstable history titles.
- **Never retry after failure:** one transient error permanently prevents a title.
- **Add a regeneration button:** expands product state beyond the explicit requirement to stop after success.

### Rationale and tradeoffs

The saved field itself is a reliable request gate, without extra timestamps/state. Titles remain stable and calls are saved; users currently cannot manually regenerate an unsatisfactory title.

### Impact

- `hasAITitle` defines validity for both request gating and display.
- Refinement batching, failure handling, and persistence stay unchanged.

### Validation and files

- XCTest covers valid/missing/blank titles and persistence; unsigned Debug validates conditional request wiring.
- `Sources/History/MeetingHistory.swift`, `Sources/App/MeetingStage.swift`, `Tests/MeetingHistoryStoreTests.swift`, AI reference.

---

<a id="dec-20260904-002"></a>
## DEC-20260904-002: Generate and persist meeting titles independently alongside refinement

- **Date:** 2026-09-04
- **Status:** Superseded
- **Superseded by:** [003](#dec-20260904-003) changes regeneration; [DEC-20260905-006](#dec-20260905-006) changes title language/length. Independent requests, storage, and display remain.
- **Scope:** Post-meeting AI orchestration, history model, presentation

### Context

Date-only history titles did not identify content. Refinement already explicitly sends transcripts to AI, making a content title useful in the same operation, without coupling it to partial batch success.

### Decision

- Refine/Refine Again starts separate Chat Completions requests for refinement and title. Title uses bounded original ASR input without waiting for refined text.
- Evaluate/save each independently. Failure, cancellation, or invalid output in one does not discard the other's success. At adoption, a successful new title replaced the old one on repeated refinement.
- `aiTitle` originally stored a cleaned Simplified Chinese title. Sidebar/details prioritize valid titles while retaining start time; absent titles use the date deterministically.
- `MeetingTitleGenerator` owns prompt/budget while sharing provider/parsing. Selection changes cancel both tasks; check operation token and record ID before writing.

### Rejected alternatives

- **Title in each batch response:** duplicates titles, lacks a global view, and couples title semantics to batch failures.
- **Wait for all refinement:** adds latency and unnecessarily lets refinement failure block titles.
- **Fail refinement when titles fail:** the outputs have no consistency dependency.
- **Hide dates entirely:** loses chronological context.

### Rationale and tradeoffs

Separate requests match different output/failure contracts while reusing HTTP infrastructure. This originally added one short request per refinement. A 6,000-character budget can bias long multi-topic meeting titles toward recent topics.

### Impact

- Refinement starts two cancellable tasks; button progress still describes transcript batches, while titles complete independently.
- Add an optional SwiftData title field and persist success immediately to update SwiftUI queries.
- Send meeting text once more to the configured provider, never audio.

### Validation and files

- XCTest covers JSON, length, ordering, provider calls, persistence, and date fallback; unsigned Debug validates SwiftData/concurrency wiring.
- `Sources/Insights/MeetingTitleGenerator.swift`, `Sources/App/MeetingStage.swift`, `Sources/History/MeetingHistory.swift`, `Sources/App/MeetingSidebar.swift`, title/history tests, session/AI references.

---

<a id="dec-20260904-001"></a>
## DEC-20260904-001: Normalize custom AI URLs and make model discovery optional

- **Date:** 2026-09-04
- **Status:** Superseded
- **Superseded by:** [004](#dec-20260904-004) raises the model capability requirement. URL normalization and optional discovery remain.
- **Scope:** AI configuration, OpenAI-compatible I/O, settings interaction

### Context

Custom services required exact base URLs and model IDs. Provider documentation variously supplies hosts, `/v1` bases, or full endpoints; a generic URL label left path appending unclear. Model IDs also often required manual documentation/dashboard lookup.

### Decision

- Keep one API URL field accepting bare hosts, path-containing bases, or complete Chat Completions URLs, with a visible final request URL. Bare remote hosts become HTTPS `/v1/chat/completions`; localhost/loopback become HTTP. Existing paths append only `/chat/completions`.
- Derive sibling `/models`, use the same Bearer key, and provide a selection menu after success while keeping model ID editable.
- Discovery is optional. Missing endpoint, empty list, or nonstandard structure shows an explanation while manual entry remains available.
- Remove the old `customBaseURL` setting path without migration/compatibility reads.

### Rejected alternatives

- **Require a `/v1` base:** exposes path rules and cannot fit gateways with different version paths.
- **Require full endpoints only:** explicit but harder to copy from common host/base documentation.
- **Require `/models` success:** rejects otherwise functional compatible services.
- **Gateway-specific discovery adapters:** standard sibling `/models` plus manual entry already meets requirements.

### Rationale and tradeoffs

Deterministic normalization reduces required API knowledge; the request preview makes it visible. Standard discovery covers Cherry Studio/common services; manual entry covers others. Hosts not using `/v1` still need their actual path, and nonstandard discovery endpoints are not guessed.

### Impact

- Settings presents normalization/discovery; provider owns HTTP I/O.
- Save/test validity depends on URL/key/model completeness, not discovery success.
- Resolver changes must update tests so preview and actual requests cannot diverge.

### Validation and files

- XCTest covers remote/loopback hosts, version paths, full endpoints, model URL derivation, invalid URLs, model decoding; unsigned Debug validates integration.
- `Sources/AI/OpenAICompatibleProvider.swift`, `Sources/AI/LLMProvider.swift`, `Sources/AI/AISettings.swift`, `Sources/App/SettingsView.swift`, `Tests/OpenAIEndpointResolverTests.swift`, AI reference.

---

<a id="dec-20260903-004"></a>
## DEC-20260903-004: Select source and target independently; bypass same-language translation

- **Date:** 2026-09-03
- **Status:** Accepted
- **Scope:** Language selection, recognition/translation, history, refinement

### Context

The old modes bundled English-to-Chinese and direct Chinese display, making one side appear selectable and the other static. They could not express Chinese-to-English or direct English. Locale, Translation, recovery, and refinement all depended on this mode, so copy changes alone were insufficient.

### Decision

- Give source and target separate clickable menus, each offering fixed English/Simplified Chinese names. Lock both after session start.
- Represent four combinations. Source chooses both ASR locales; different languages create Translation in the chosen direction. Matching languages create neither session nor request and use recognized text as target.
- Persist the full pair in `MeetingRecord.language`; recovery, captions, export, and refinement derive from it. Use distinct stored values without compatibility parsing, migrations, or fallbacks.

### Rejected alternatives

- **Retain two presets:** cannot express independent direction and leaves target apparently static.
- **Translate same-language text anyway:** adds resources, latency, and failure without semantic benefit.
- **Swap UI labels only:** leaves locale, recovery, and refinement using the wrong direction.

### Rationale and tradeoffs

A fixed language enum plus a full pair is the minimal model for all four behaviors. `source != target` uniquely determines translation, avoiding contradictory switches. New languages require verifying both Speech and Translation capabilities.

### Impact

- English vocabulary enters recognition only for English sources.
- Cross-language captions/exports show target and source; same-language output avoids duplicates.
- Refinement retranslates in the saved direction or cleans source only.

### Validation and files

- XCTest covers labels, combinations, bypass, persisted values, refinement prompts. The signed app was used to inspect both menus' clickable appearance.
- `Sources/Meeting/MeetingModels.swift`, `Sources/Meeting/CaptureCoordinator.swift`, `Sources/Meeting/TranslationPump.swift`, `Sources/App/MeetingStage.swift`, `Sources/History/MeetingHistory.swift`, `Sources/Insights/TranscriptRefiner.swift`, `Tests/MeetingLanguageTests.swift`, pipeline reference.

---

<a id="dec-20260903-003"></a>
## DEC-20260903-003: Explicitly save English vocabulary and freeze it per recording stage

- **Date:** 2026-09-03
- **Status:** Superseded
- **Superseded by:** [DEC-20260904-005](#dec-20260904-005) changes cloud separation. Local recognition, explicit saving, stage snapshots, and caching remain.
- **Scope:** Local ASR, settings persistence, dual-stream consistency

### Context

English ASR used 41 hardcoded names/acronyms. Meeting terminology changes faster than releases. If both running recognizers observed mutable settings directly, they could use different versions during the same stage.

### Decision

- Add a separate Vocabulary tab, one word/phrase per line, persisted to UserDefaults only on Save.
- Keep the 41 defaults on first launch. Save trims whitespace/removes blank lines and case-insensitive duplicates; empty vocabulary is valid.
- Start/resume freezes one snapshot for both system and microphone recognizers. Mid-recording saved changes wait until the next English start/resume.
- Supply the list to both `AnalysisContext.contextualStrings` and local `SFCustomLanguageModelData`. No custom pronunciations, weights, or output string replacement. Cache by locale/content fingerprint.

### Rejected alternatives

- **Update running recognizers on edit:** requires rebuilding both Speech lifecycles and abruptly changes current context.
- **Use contextual strings only:** discards an already validated custom-model path.
- **Correct final output with replacements:** changes text deterministically rather than providing the requested model bias and risks meaning.

### Rationale and tradeoffs

Explicit Save/snapshots make behavior predictable and streams consistent. Content fingerprints reuse identical models without stale-cache hits. Changes wait for a new stage, and first use of a new list requires model preparation.

### Impact

- At adoption, vocabulary and custom models stayed entirely local, separate from optional cloud insights.
- Empty English vocabulary skips custom models; Chinese recognition is unchanged.
- Future format/timing/hint changes must check snapshots and cache identity together.

### Validation and files

- XCTest covers defaults, normalization, and persisted empty vocabulary; unsigned Debug verifies Speech APIs and Swift 6 boundaries.
- `Sources/Capture/SpeechVocabularySettings.swift`, `Sources/Capture/SpeechVocabularySettingsView.swift`, `Sources/Capture/NativeSpeechEngine.swift`, `Sources/Capture/CustomSpeechLanguageModel.swift`, `Sources/Meeting/CaptureCoordinator.swift`, `Tests/SpeechVocabularySettingsTests.swift`, pipeline reference.

---

<a id="dec-20260903-002"></a>
## DEC-20260903-002: Separate insights from refinement and bound recent AI context

- **Date:** 2026-09-03
- **Status:** Superseded
- **Superseded by:** [DEC-20260904-004](#dec-20260904-004) replaces tolerant JSON parsing. Responsibility separation and context budgets remain.
- **Scope:** AI ownership, input budgets, live-session isolation

### Context

Live insights are low-latency, latest-snapshot, single-flight work. Refinement is serial, line-based, and partially successful. One engine mixed their state/helpers. Sending the entire meeting also exceeded the smallest built-in 8K context on long sessions.

### Decision

- `InsightEngine` owns live/history structured insights; `TranscriptRefiner` separately owns proofreading, retranslation, glossary batches.
- Live/history insights send only the latest 6,000 characters, preferring complete lines: a conservative provider-independent budget without per-model tokenizers/configuration.
- Bind live requests to a session token; cancel known work and reject late responses on reset. Both engines then shared provider settings and tolerant JSON parsing, not business state.

### Rejected alternatives

- **Keep an all-purpose engine:** incompatible execution/failure models keep expanding one class.
- **Always send full text:** unreliable with known 8K models and unbounded time/cost growth.
- **Configurable tokenizers/budgets:** current provider/model variety did not justify that complexity.

### Rationale and tradeoffs

Each engine owns one state machine. Recent context fits “what to do next” and the smallest model. Early meeting content can leave the window, and character limits approximate tokens.

### Impact

- Insight schema/triggers belong in the insight engine; line refinement belongs in the refiner.
- AI results remain additive, preserving original ASR facts.
- A future whole-meeting summary should be a separate hierarchical use case, not removal of the live budget.

### Validation and files

- XCTest covers newest complete lines, oversized-line suffixes, and the then-supported fenced JSON parser.
- `Sources/Insights/InsightEngine.swift`, `Sources/Insights/TranscriptRefiner.swift`, `Sources/App/InsightInspector.swift`, AI reference, `Tests/InsightEngineTests.swift`.

---

<a id="dec-20260903-001"></a>
## DEC-20260903-001: Model lifecycle explicitly and finalize through awaitable I/O boundaries

- **Date:** 2026-09-03
- **Status:** Accepted
- **Scope:** Session state, audio/ASR/translation concurrency, persistence, validation

### Context

Multiple booleans/timestamps composed session state; capture/ASR depended on unsafe Sendable; ending waited a fixed 900 ms before saving. Nothing proved final audio, ASR, or authoritative translation had completed, and old tasks could write into new meetings. SwiftData errors were swallowed and container failure silently used memory while UI could claim saved. No test target existed; concurrency checking was minimal.

### Decision

- One `idle/starting/recording/pausing/paused/stopping` state drives derived UI flags.
- `NativeSpeechEngine` actor owns bounded audio, converter, and Speech objects. Stop drains audio, finalizes Speech, and awaits main-actor store writes.
- `TranslationBridge` counts pending/in-flight work. Pause/end awaits idle, capped at five seconds for the system service. ASR/translation carry session UUIDs to reject stale writes.
- Persistence throws errors; final text and ended status share one save; failures roll back. Container failure blocks meetings, without an in-memory fallback. Pause/final-save failure retains mounted state for retry.
- Both targets use complete concurrency checking; establish XCTest for deterministic invariants.

### Rejected alternatives

- **More boolean guards:** cannot represent transitional states and still permits contradictions.
- **Longer fixed sleeps:** never proves completion and delays successful paths.
- **Memory storage after container failure:** misleads users about persistence.
- **Lower checking/unsafe annotations:** hides executor violations without proving ownership.

### Rationale and tradeoffs

Explicit transitions and awaited boundaries make lifecycle reviewable. Actor isolation/complete checking turn conventions into compiler rules. The accepted tradeoff is ending with saved source if Translation exceeds five seconds.

### Impact

- `CaptionStore` owns transcript state only; coordinator owns lifecycle.
- System audio is required. Initial mic failure may continue system-only, with visible errors for both failure types.
- Translation failure is explicit Section `.failed`, retaining source.
- Changes to Section/scheduling/persistence logic require updated, executed tests.

### Validation and files

- Regenerate with XcodeGen; unsigned Debug and macOS XCTest are the minimum gate.
- `Sources/Meeting/MeetingModels.swift`, `Sources/Meeting/CaptureCoordinator.swift`, `Sources/Capture/NativeSpeechEngine.swift`, `Sources/Meeting/TranslationBridge.swift`, `Sources/History/MeetingHistory.swift`, `project.yml`, pipeline/session references, `Tests/`.

---

<a id="dec-20260902-002"></a>
## DEC-20260902-002: Organize source by domain responsibility

- **Date:** 2026-09-02
- **Status:** Accepted
- **Scope:** Source directories, module boundaries, navigation

### Context

App assembly, capture, meetings, history, and AI were flat under `Sources/`. More files made user paths, I/O boundaries, and downstream ownership hard to infer.

### Decision

At adoption, use seven top-level responsibility directories: `App`, `Capture`, `Meeting`, `History`, `Insights`, `Shared`, `Resources`. Group business files by domain, not View/Model/Service. XcodeGen recursively includes `Sources/` without a target/abstraction per directory.

### Rejected alternatives

- **Stay flat:** navigation was already difficult and would worsen.
- **Group by technical type:** scatters one user path and weakens domain cohesion.
- **Immediately split targets/packages:** no evidence for compile-time separation; adds premature access-control/build complexity.

### Rationale and tradeoffs

Domain folders express ownership/change scope with one target and no runtime cost. Boundaries are organizational, not compiler-enforced. Revisit target separation for independent reuse/testing or meaningful build gains.

### Impact

- `project.yml` keeps `Sources/` as its only source root, with metadata in `Sources/Resources/Info.plist` and `Sources/Resources/SameWave.entitlements`.
- Installer, README, reference routing, and source links use domain paths.
- Prefer existing domains for new files; add a top-level directory only for a stable new responsibility.

### Validation and files

- XcodeGen regeneration and unsigned Debug passed.
- `project.yml`, README, architecture and development references.

---

<a id="dec-20260902-001"></a>
## DEC-20260902-001: Establish a central project decision log

- **Date:** 2026-09-02
- **Status:** Accepted
- **Scope:** Engineering workflow and documentation

### Context

Domain docs described current architecture but lacked a stable place for context, rejected alternatives, and long-term effects. Updating only current behavior loses rationale and invites repeated debate or uninformed reversals.

### Decision

Use this file as the sole lightweight decision log. Record lasting product, architecture, state, data, security, dependency, and workflow decisions before task completion; domain references describe current state in parallel.

### Rejected alternatives

- **Source comments only:** scattered and poor for cross-module decisions/replacement history.
- **One ADR file per decision:** excessive directory/template overhead at this scale.
- **Mix decisions into domain references:** good for current conclusions, poor for chronology/alternatives/evolution.

### Rationale and tradeoffs

A single searchable, low-maintenance log complements domain references. Newest-first ordering, stable IDs, and selective scope control growth.

### Impact

- `AGENTS.md` gains triggers and completion criteria for recording decisions.
- `doc/README.md` links the maintained log.
- Important changes update both rationale and current-system documentation.

### Validation and files

- Confirmed relative links from `AGENTS.md` and `doc/README.md` resolve here.
- [`AGENTS.md`](../AGENTS.md), [`doc/README.md`](README.md), [`doc/DECISIONS.md`](DECISIONS.md).

---

## New decision template

Copy above the newest decision and remove inapplicable guidance.

```markdown
## DEC-YYYYMMDD-NNN: Short, specific decision title

- **Date:** YYYY-MM-DD
- **Status:** Accepted
- **Scope:** Affected product or technical area

### Context

The problem, constraints, and confirmed facts prompting the decision.

### Decision

The adopted approach and its boundaries.

### Rejected alternatives

- **Option A:** Why it was rejected.

### Rationale and tradeoffs

Why this approach fits and which costs are accepted.

### Impact

Effects on product, code, data, operations, security, and future work.

### Validation and files

Supporting tests, experiments, metrics, requirements, and source locations.
```
