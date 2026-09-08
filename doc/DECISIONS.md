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

<a id="dec-20260908-004"></a>
## DEC-20260908-004: Separate AI enablement from saved connection configuration

- **Date:** 2026-09-08
- **Status:** Accepted
- **Scope:** App-wide AI availability, cancellation, and Settings behavior
- **Replaces:** The rejection of a global enable switch in [DEC-20260905-003](#dec-20260905-003). Shared configuration ownership and provider boundaries remain adopted.
- **Context:** Issue #21 requires temporarily disabling AI while retaining a configured provider. Insights can be queued across meetings, refinement and titles continue in the background, and extraction retries retain their original provider. Blocking only new provider creation would leave these operations running.
- **Decision:** Persist one app-wide switch, on by default, independently of connection preferences. Apply it immediately, including when the connection draft is invalid or unsaved. Cancel reverts only connection edits. Effective availability combines enablement with valid configuration. Disabling synchronously cancels all active AI owners and clears queued requests through app assembly; request entry points also enforce the switch. Operation cancellation and ownership tokens reject late responses and prevent subsequent batches. Service tests and model discovery obey the same switch. Re-enabling restores ordinary triggers without restarting canceled manual operations; eligible automatic ticks retain their recording schedule.
- **Rejected alternatives:** Clearing credentials loses a reusable configuration. A switch that only gates provider creation permits retained providers and queued work to continue. A switch committed with Save delays stopping AI and can be blocked by unrelated invalid draft fields. Per-feature switches duplicate the requested app-wide control. View-lifetime observers cannot reliably cancel background work.
- **Rationale/tradeoffs:** One immediate preference provides a predictable stop action while each existing owner retains its own cancellation and persistence responsibilities. Cancellation cannot recall data already sent to a provider. Stored credentials, saved and unsaved results, extraction candidates, and local capture/translation/history/vocabulary remain available; Retry Save is local and stays enabled. No new provider abstraction, persistence model, migration, or dependency is introduced.
- **Validation:** Controlled-provider regressions cover persisted enablement, connection-draft independence, all generation entry points, automatic resumption, queued work across meetings, background refinement/title cancellation, extraction retry and local saving, and late responses. Draft tests also cover cancellation before a scheduled request starts. Native render tests cover compact bilingual settings and preparation title/Done alignment. XcodeGen and unsigned Debug passed; full English tests passed 237/237 and Chinese localization/rendering tests passed 16/16 on `SameWave`, `platform=macOS,arch=arm64`. The signed desktop app passed switch persistence, disabled-action, configuration-retention, preparation scrolling/dismissal, signature, and process checks. See the [development guide](06-development-and-validation.md) for details.
- **Files:** `Sources/AI/AISettings.swift`, `Sources/AI/AISettingsDraft.swift`, `Sources/App/SameWaveApp.swift`, `Sources/Meeting/CaptureCoordinator.swift`, AI consumers, `Tests/AIAvailabilityTests.swift`, `Tests/AISettingsDraftTests.swift`, `Tests/MainViewRenderingTests.swift`.

---

<a id="dec-20260908-003"></a>
## DEC-20260908-003: Generate AI Insights in the active interface language

- **Date:** 2026-09-08
- **Status:** Accepted
- **Scope:** Insight generation language and immutable result versions
- **Replaces:** The English-only insight output in [DEC-20260908-001](#dec-20260908-001) and [DEC-20260905-006](#dec-20260905-006). Native localization, generated meeting titles, English prompt source text, export templates, and documentation decisions retain their existing scope.
- **Context:** The user requested that AI Insights follow the app language. The previous system prompt forced English even when the interface was Chinese. All insight request paths already share one system prompt and response contract.
- **Decision:** Resolve English or Simplified Chinese from the native bundle's active language in the shared insight system prompt. Require conclusions, points, and every summary item to use that language, independently of transcript language and language requests in analysis instructions. Preserve proper names, justified vocabulary spelling, and JSON field names. Apply the same prompt to automatic, individual, batch, and full-summary requests; the context preflight continues counting that actual prompt. Language changes retain the established relaunch boundary. Keep saved snapshots immutable and append a new version when the user regenerates. Export includes each saved version verbatim.
- **Rejected alternatives:** Reading the pending picker value could disagree with the currently displayed language. A separate insight-language setting would duplicate the requested app-wide choice. Translating stored results or translating an English response in a second request would rewrite history or add unnecessary work and another failure boundary. Localizing JSON field names would break the response contract.
- **Rationale/tradeoffs:** One request produces content in the selected interface language without another model call, client translation, or persistence change. Existing English versions remain English until the user requests a new version. Language adherence is part of the model prompt; structural validation remains independent of language.
- **Impact and validation:** XcodeGen, unsigned Debug build, and source/link/translation audits pass. `SameWave` on `platform=macOS,arch=arm64` passes 227/227 full English/US tests and 14/14 Chinese/CN localization/rendering tests. Controlled-provider tests verify all four generation paths with a different meeting language, exact request instructions, result parsing/persistence, old-version retention, and export. Chinese focused-result, summary, and editor renders were visually inspected; both languages passed rendering assertions. The signed desktop app was replaced and launched in its existing Chinese preference; signature/process checks and opening/cancelling the native insight editor passed. No real provider generation was run; model adherence is covered by the documented synthetic-meeting smoke procedure.
- **Files:** `Sources/Insights/InsightModels.swift`, `Sources/Meeting/InsightDefinitionEditor.swift`, `Sources/Resources/Localizable.xcstrings`, `Tests/LocalizationTests.swift`, `Tests/MainViewRenderingTests.swift`, `Tests/Phase2TestSupport.swift`, README and product/AI/development references.

---

<a id="dec-20260908-002"></a>
## DEC-20260908-002: Expose the native app language preference in General settings

- **Date:** 2026-09-08
- **Status:** Accepted
- **Scope:** Settings entry point, preference ownership, and language activation
- **Replaces:** The system-settings-only language entry point in [DEC-20260908-001](#dec-20260908-001). Its native catalogs, launch-time activation, and content boundaries remain adopted.
- **Context:** The user requested an in-app selector with Follow System, English, and Chinese, defaulting to Follow System. SwiftUI labels, Foundation messages, AppKit menus, and permission resources must continue selecting the same language.
- **Decision:** Add General as the initial Settings tab. Save explicit selections immediately to the app-domain `AppleLanguages` preference and remove that key for Follow System. Read the persistent app domain to distinguish an override from inherited global languages, and use native bundle matching for an existing macOS per-app preference. Keep this preference independent of AI drafts and vocabulary edits. Explain beside the picker that the user must quit and reopen SameWave to apply a change. Let native bundles resolve the language on the next launch.
- **Rejected alternatives:** A separate application language key would compete with the native macOS setting. Storing the current system language for Follow System would stop following future system changes. Updating only SwiftUI's locale would leave dynamic messages and native UI inconsistent. Automatic relaunch on selection would interrupt meetings and pending work.
- **Rationale/tradeoffs:** One native preference controls every localization boundary without replacing bundle lookup or maintaining parallel translation state. Selection saves immediately, while the current app session keeps its launch language. The user decides when to quit, and existing session persistence handles that normal exit.
- **Impact and validation:** XcodeGen and unsigned Debug build pass. `SameWave` on `platform=macOS,arch=arm64` passes 224/224 full English/US tests and 11/11 Chinese/CN preference, localization, and rendering tests. Tests cover default selection, persistence, native language matching, override removal, unrelated/global preferences, all three visible selections, and retained AI/vocabulary drafts. The source/link/translation audit passes. After signed desktop installation, native UI checks verified Chinese and English across quit/reopen, then restored Follow System and confirmed the override is absent. Done closes General with Return.
- **Files:** `Sources/App/AppLanguageSettings.swift`, `Sources/App/GeneralSettingsView.swift`, `Sources/App/SettingsView.swift`, `Sources/Resources/Localizable.xcstrings`, `Tests/AppLanguageSettingsTests.swift`, settings/rendering fixtures, README, product/development references.

---

<a id="dec-20260908-001"></a>
## DEC-20260908-001: Localize the interface with native English and Simplified Chinese catalogs

- **Date:** 2026-09-08
- **Status:** Superseded for the language settings entry point by [DEC-20260908-002](#dec-20260908-002) and generated insight language by [DEC-20260908-003](#dec-20260908-003). Native catalogs, launch-time activation, and preserved-content boundaries remain adopted.
- **Scope:** Interface language, localization resources, content boundaries, and validation
- **Replaces:** The English-only interface, permission text, and UI metadata formatting in [DEC-20260905-006](#dec-20260905-006). Its app identity, English prompts/generated AI output/export templates, and documentation decisions remain adopted.
- **Context:** Issue #17 requests English and Chinese app support. UI literals alone do not cover status/errors, dynamic control labels, counts, permission explanations, or summary headings. Some English labels also feed prompts and export, while editable titles and saved content must remain verbatim.
- **Decision:** Use Apple string catalogs with English source keys and Simplified Chinese translations. Let macOS choose the app language, including its per-app language preference, on launch. Use SwiftUI localized literals for view copy and `String(localized:)` for dynamic app-owned messages. Put singular/plural and multiple-count substitutions in the catalog. Localize displayed dates through native formatting; keep explicit English export dates. Localize fixed summary headings only at the view boundary. Initialize a new editable overview title in the app language, then treat it as persisted user content. Do not localize storage/protocol identifiers, speech language identifiers, prompt language names, documents, vocabulary, editable titles, transcripts, or saved AI results. Keep source copy, prompts, generated AI content, export templates, and documentation in English.
- **Rejected alternatives:** A custom language manager, parallel settings preference, and in-process switching would duplicate native app language selection and require rebuilding cached state. Translating arbitrary dynamic strings by lookup could alter user content that happens to match a UI key. Translating persisted records or model output would broaden an interface request into data rewriting. English word fragments for counts do not support correct pluralization or Chinese grammar.
- **Rationale/tradeoffs:** Native catalogs provide compiled resource selection, translator context, interpolation, and plural rules without a dependency or compatibility layer. Language changes require reopening the app. System/provider error details retain their original wording; app-owned wrappers are translated. Editable titles created in an earlier language remain in that language unless edited.
- **Impact and validation:** XcodeGen and unsigned Debug build pass. `SameWave` on `platform=macOS,arch=arm64` passes all 219 tests with English/US and 6 localization/rendering tests with Simplified Chinese/CN. Tests cover compiled UI/permission bundles, unsupported-language selection, zero/one/multiple counts, two independent plural counts, diagnostic interpolation, native minimum-size views, and preserved content/export. The English source/link audit now also validates complete translations and placeholder contracts. Native rendered Chinese preparation, settings, vocabulary, summary, and editor views were inspected.
- **Files:** `Sources/Resources/Localizable.xcstrings`, `Sources/Resources/InfoPlist.xcstrings`, `project.yml`, presentation/status/error call sites, `Tests/LocalizationTests.swift`, native rendering/export/identity tests, `scripts/check_localizations.py`, `AGENTS.md`, product/development references.

---

<a id="dec-20260907-004"></a>
## DEC-20260907-004: Separate conversational turns from cumulative recognition

- **Date:** 2026-09-07
- **Status:** Accepted
- **Scope:** Live source ownership, interruption ordering, and caption presentation
- **Replaces:** The final-bound Section ownership and translation-busy presentation in [DEC-20260907-003](#dec-20260907-003). Its source-keyed translation mailbox, progressive generations, deadlines, cancellation, and lifecycle behavior remain adopted.
- **Context:** Remote speech after a microphone reply continued inside an older paragraph because Sections stayed tied to each recognizer's final result. The user also requested removal of Translating. A native English DictationTranscriber probe exposed only whole-hypothesis interim timing; word times arrived at finalization. A SpeechDetector probe returned no activity results, including for padded silence. A signed-app counterexample showed that switching on every added word instead creates many tiny paragraphs during simultaneous input.
- **Decision:** Track recognition activity independently of cumulative source ownership. Continuous overlapping growth keeps each speaker's active paragraph. After at least one second without added words, a speaker returning after an intervening speaker opens a new Section without waiting for ASR finalization. Inactivity without an intervening speaker does not split the latest paragraph. Use Apple's NaturalLanguage tokenizer and Swift collection differences to retain Section ownership for matched/replaced words and interior corrections; only unmatched trailing words refresh the monotonic activity time. A final corrects and commits each owned fragment once and seals an interrupted completed contribution. Remove wholly retracted fragments without reusing IDs. Pause/end preserves all remaining fragments. New Sections freeze bounded same-speaker context including unfinished source. Render source once until translation arrives, then target above distinct source, with no busy text/spinner and explicit source-preserving failures.
- **Rejected alternatives:** Final-only turn boundaries repeat the reported failure. Moving/copying cumulative text duplicates or reorders speech. Switching on every callback or new word fragments continuous overlap; punctuation-only corrections must not refresh activity. Live word timestamps were not available in the measured English path, and a detector that did not emit results cannot become a production prerequisite. Forcing recognition finalization or adding another engine changes the I/O boundary without resolving text ownership by itself.
- **Rationale/tradeoffs:** One second of recognition inactivity provides a bounded distinction between dense overlap and returning speech using current callbacks, without waiting an extra second after the returning words arrive. This is an observed-text rule, not acoustic VAD: delayed/batched results can shift boundaries, and wholesale rewrites/tokenization changes can blur corrections versus growth. Sealed text remains correctable. The explicit rule is tested with a controlled monotonic clock rather than timing sleeps or a claim of perfect diarization.
- **Impact and validation:** XcodeGen, unsigned Debug build, and full SameWave XCTest passed 213/213 on `platform=macOS,arch=arm64`. The new regression suite covers both speaker orders before finalization, dense simultaneous growth, the inactivity boundary, correction-only activity, repeated interruptions/words, native English snapshot replay, Chinese, late multi-fragment finals, retractions/stale translations, frozen context, stop/restore, translation deduplication, and ordered history/export. Native renders show source before translation in three paragraphs with no Translating in pending/progressive/completed/failed states. The old 203-test result remains evidence of the superseded behavior, not proof of this correction. Final build/test and signed-app evidence are recorded in [development validation](06-development-and-validation.md).
- **Files:** `Sources/Meeting/SpeechHypothesis.swift`, `Sources/Meeting/CaptionStore.swift`, `Sources/Meeting/CaptureCoordinator.swift`, `Sources/Meeting/CaptionsView.swift`, related XCTest files, pipeline/rendering/architecture references.

---

<a id="dec-20260907-003"></a>
## DEC-20260907-003: Preserve overlapping utterances and publish progressive translations

- **Date:** 2026-09-07
- **Status:** Superseded for unfinished-Section ownership and translation-busy presentation by [DEC-20260907-004](#dec-20260907-004); translation scheduling, progressive generations, deadlines, cancellation, and lifecycle decisions remain adopted.
- **Scope:** Live Section ownership, translation progress, consumer lifetime, and failure handling
- **Context:** Issue #13 reports captions blocking when the other speaker interrupts. The single-floor store discarded non-floor interims. Issue #12 shows continuous source with no translation: every interim incremented the required generation, rejecting all in-flight responses until input became quiet. A cancelled app-lifetime mailbox stream could not be reused, and preparation failure drained only the requests already queued. Sealing also discarded an unfinished tail when earlier sentences existed.
- **Decision:** Keep at most one unfinished Section per speaker, ordered by its first observed result. Show both interims immediately; revisions/finals remain in their original Section. Seal an interrupted Section after its final and place its next utterance after the interrupter. Seal a completed previous turn immediately on the other's first result. Split a six-sentence contribution before the next utterance, and preserve every remaining interim tail on pause/end. Translation work is keyed by source snapshot, with no redundant final/sealed pass. Publish results newer than the last displayed generation, even when newer source is pending; only the latest requested snapshot becomes done. Each Translation consumer owns its wake-up stream and identity. Cancellation, preparation failure, and a 15-second prepared-request deadline settle owned work, fail later enqueues until restart, cancel the framework session, and reject late replies. Start/resume prepares a fresh session. Empty responses fail explicitly. Restored missing translations display source/failure.
- **Rejected alternatives:** Final-only floor changes keep the reported delay. Switching on every alternating interim fragments and duplicates cumulative ASR text. Inferring word-level overlap boundaries requires timing/ownership events that the current callbacks do not supply. Strict latest-request equality starves all visible progress during dense input. Increasing delays or adding concurrent sessions does not fix state ownership. Hiding Translating without settling work would mask the defect.
- **Rationale/tradeoffs:** The change uses existing ASR callbacks, per-Section coalescing, public Apple cancellation, and ordinary MainActor isolation, without dependencies or VAD heuristics. An unfinished older utterance can continue updating during overlap; ordering follows observed ASR rather than exact acoustic onset. An earlier translation may briefly trail current source and remains marked translating. The deadline applies after preparation, allowing first-use model downloads separately. The five-second pause/end drain remains bounded independently; source is preserved when translation is incomplete.
- **Impact and validation:** XcodeGen, unsigned Debug build, and all 203 XCTest cases pass with SameWave / platform=macOS,arch=arm64. Replaces the previous rendering baseline and final-generation-only policy; UUID isolation, SwiftData IDs, and source/target storage remain. Deterministic tests cover symmetric overlapping revisions/finals, continuation, sentence splitting, interim-tail persistence, 100 rapid source updates with visible progress, coalescing fairness, idle/in-flight cancellation and restart, preparation failure before/after enqueue, empty/error responses, request deadlines, ignored cancellation, and missing translations on restore. Native rendering verifies both speakers and progress/completion/failure. The installed signed app also passed system-audio/microphone English-to-Chinese playback, pause/resume translation, and ended-history checks with synthetic speech. Natural interruption timing and recognition accuracy remain platform-dependent. See [development validation](06-development-and-validation.md) for signed-app checks and platform limits.
- **Files:** `Sources/Meeting/CaptionStore.swift`, `Sources/Meeting/MeetingModels.swift`, `Sources/Meeting/CaptureCoordinator.swift`, `Sources/Meeting/TranslationBridge.swift`, `Sources/Meeting/TranslationPump.swift`, `Sources/Meeting/CaptionsView.swift`, related XCTest files, pipeline/lifecycle/rendering references.

---

<a id="dec-20260907-002"></a>
## DEC-20260907-002: Select material insights within one generation request

- **Date:** 2026-09-07
- **Status:** Accepted
- **Scope:** Focused insight selection and generation complexity
- **Replaces:** The three-point limit and three-item summary preference in [DEC-20260907-001](#dec-20260907-001). Its model context configuration and local error behavior remain adopted.
- **Context:** The user rejected point counts as a measure of quality: a small list can still contain verbose, low-value material or bundle unrelated obligations. The user also explicitly required one AI prompt without an additional review call or special processing pipeline.
- **Decision:** Keep one provider completion per insight, with the existing frozen full original input and result contract. Remove the focused point-count maximum from Schema, validation, and prompts, and remove the three-item summary preference. Within the single prompt, select candidates by relevance to the actual question, support in original source, and effect on understanding, decisions, actions, risks, or dependencies. Apply a deletion test: omit an item if removing it would not change what the user should understand or do. Reconcile explicit corrections, merge repeated claims, preserve independent commitments, and distinguish facts, inferences, advice, support, and authorization. Missing details merit attention only when they block the decision or are assigned follow-ups. Do not invent preventive tasks from things the meeting did not decide. Keep existing text-format safeguards and the structured-summary schema; they do not determine importance. Previous AI answers are not supplied as evidence.
- **Rejected alternatives:** Restoring a different fixed count preserves the wrong selection criterion. Combining independent tasks into a single bullet hides obligations. A second editorial request adds latency, cost, and request-state complexity that the user explicitly excluded. Mechanical deletion by string similarity cannot judge decision relevance or factual distinctions.
- **Rationale/tradeoffs:** One prompt improves the selection criteria without another engine, request stage, model field, or dependency. The number of points can grow when there are more independent material facts. Semantic judgment is still model-dependent: formatting tests and shorter outputs cannot prove factual accuracy or optimal relevance.
- **Impact and validation:** XcodeGen and unsigned Debug build pass. Full SameWave / platform=macOS (arm64) XCTest passes 190/190. Schema/parser tests accept twenty points without cutting content and verify no minimum or maximum count while retaining text validation. A disposable probe used the configured service with four synthetic cases: later WFH correction with repeated unrelated chatter, four remaining independent obligations after one completion, an absent topic, and release advice with an unconfirmed cause. The outputs preserved the four obligations and dates, HR authority, proposal uncertainty, and empty points for the absent topic. The release answer still included an unagreed-date observation; this is not evidence of perfect relevance. The probe did not send personal meeting content or alter saved meetings. No experimental review stage was added to the app.
- **Files:** `Sources/Insights/InsightModels.swift`, `Tests/InsightDensityTests.swift`, `README.md`, `doc/04-ai-insights-and-refinement.md`, `doc/phase-2-spec.md`, `doc/phase-2-validation.md`.

---

<a id="dec-20260907-001"></a>
## DEC-20260907-001: Configure model capacity and keep focused insights concise

- **Date:** 2026-09-07
- **Status:** Superseded for the three-point limit and summary item preference by [DEC-20260907-002](#dec-20260907-002); model context configuration and local error reporting remain adopted.
- **Scope:** Insight context configuration, local error reporting, and generated information density
- **Replaces:** The initial 32,768-token default and generic provider-error presentation in [DEC-20260905-009](#dec-20260905-009). Full original evidence, user configuration, immutable snapshots, and explicit oversized-input failures remain adopted.
- **Context:** A 97-section Chinese meeting with 8,388 original characters crossed the default conservative byte-based preflight estimate partway through recording. The local error claimed the service rejected the request, while cards retained earlier successful results. The configured service was being used with a 1M model. Focused advice also expanded to twelve points and 3,340 characters, diluting the useful priorities as the meeting grew.
- **Decision:** Expose Model context window (tokens) in AI Services with a 1,000,000-token default and the existing configurable range. Keep explicitly saved values. Save applies the value to newly created requests; queued/active inputs and saved versions retain their frozen source, provider, and window. Use a distinct local context-window error with actionable Settings instructions. Keep conservative preflight and full source; the provider remains authoritative about its actual capacity. Focused results request one direct conclusion of at most 300 characters and at most three prioritized points of at most 240 characters each, enforced by Schema and client validation. Merge overlapping advice, exclude generic filler, and use empty points when the requested topic lacks relevant discussion. Structured summaries prefer three short items per part but retain their existing allowance for distinct material actions, decisions, and blockers.
- **Rejected alternatives:** A fixed low ceiling prevents ordinary meetings from reaching capable models. Guessing capacity from model names or treating byte counts as exact tokenization is unreliable across compatible gateways. Silently cutting source would lose early agreements or later corrections. Hiding a long answer behind disclosure does not improve generated information density. Applying the focused three-point ceiling to complete summaries could omit separate commitments.
- **Rationale/tradeoffs:** User-declared capacity matches the selected model without adding discovery or tokenizer dependencies. The conservative estimate can still reject input near the configured limit, and a 1M default is not proof of server capacity. Focused cards trade exhaustive coverage for prioritized guidance; immutable versions and structured summaries retain their separate purposes. Semantic ranking remains model-dependent.
- **Impact and validation:** XcodeGen, unsigned Debug build, and all 190 XCTest cases pass on SameWave / platform=macOS (arm64). Tests reproduce a complete 97-section/273-term request rejected at 32K and accepted after saving 1M, verify draft isolation and frozen active input, retain prior results after failure, and check matching Schema/client density limits. The signed desktop app passes signature and process checks. Two new saved results from the reported meeting contain all 97 original sections, use 1M, and have three points each; focused advice is 715 characters. No transcript or historical snapshot was rewritten.
- **Files:** `Sources/AI/AISettings.swift`, `Sources/AI/AISettingsDraft.swift`, `Sources/AI/AISettingsView.swift`, `Sources/AI/LLMProvider.swift`, `Sources/Insights/InsightModels.swift`, `Tests/InsightContextWindowTests.swift`, `Tests/InsightDensityTests.swift`, `doc/04-ai-insights-and-refinement.md`.

---

<a id="dec-20260906-010"></a>
## DEC-20260906-010: Select recognition vocabulary by usefulness and preserve meaningful names

- **Date:** 2026-09-06
- **Status:** Accepted
- **Scope:** Markdown vocabulary extraction policy
- **Context:** Issue #10 reports too many ordinary words and repeated product phrases. The user clarified that its proposed universal whitespace splitting is advisory and authorized a judgment-based prompt improvement. Splitting every personal or product name can leave ordinary, ambiguous components that are less useful to speech recognition.
- **Decision:** Prioritize explicitly present abbreviations/acronyms, personal names, internal codenames, and specialized terminology. Ordinary words require both central relevance and repetition; headings/capitals alone do not establish value. Prefer compact spoken units, reuse meaningful product roots, and preserve multiword names when splitting loses identity. Keep this semantic choice in the prompt, without unconditional client tokenization or a static English blacklist. The 50-term ceiling is not a quota; prompt examples must never be copied when absent from the source.
- **Rejected alternatives:** Requiring every abbreviation to name an entity excludes useful specialized acronyms. Universal whitespace splitting breaks names such as Grace Hopper and Visual Studio. Generic stopword filtering cannot distinguish a term's contextual importance.
- **Rationale/tradeoffs:** Recognition value depends on context and naming, so the provider handles relevance while existing client validation enforces structure, size, and deduplication. Model judgment remains variable; deterministic tests verify the prompt contract and that multiword responses survive review normalization, not empirical extraction accuracy.
- **Impact and validation:** Replaces the named-entity-only selection rule recorded in [DEC-20260904-012](#dec-20260904-012). Existing batching, retries, review, saved vocabulary, and explicit sends remain unchanged. Vocabulary generator and full app tests pass; no real-provider extraction benchmark was run.
- **Files:** `Sources/Insights/VocabularyGenerator.swift`, `Tests/VocabularyGeneratorTests.swift`, `doc/02-live-captions-and-translation.md`, `doc/04-ai-insights-and-refinement.md`.

---

<a id="dec-20260906-009"></a>
## DEC-20260906-009: Keep explicit AI work with its meeting across navigation

- **Date:** 2026-09-06
- **Status:** Accepted
- **Scope:** AI task ownership, cancellation, scheduling, and result persistence
- **Context:** Issue #9 exposed view-owned refinement/title tasks and selection-driven insight cancellation. Leaving a meeting discarded progress, and a new manual request could cancel another meeting's work.
- **Decision:** CaptureCoordinator retains a MeetingRefinementController per meeting for the app session. It owns refinement/title task handles, progress, and errors; the refiner handles batches and history owns writes. Selection and view recreation do not cancel explicit AI work. Insights retain per-meeting batch identities and one app-wide ordered queue under the existing six-active-request cap. Standalone requests wait when all slots are occupied. Replacements and Stop affect only their own meeting; pause/end stops automatic work while manual requests keep their frozen input. Successful deletion invalidates that meeting's work before any late response can write. Completion checks tokens and original UUID ownership, independent of selection. The sidebar displays active/queued work. Completed results persist; unfinished jobs and errors last only until app exit.
- **Rejected alternatives:** Retaining hidden views would leave task ownership in presentation. Cancelling on selection contradicts expected navigation behavior. One engine per meeting would lose the shared concurrency cap. A persistent background-job system adds restart semantics outside this requirement. Saving by selected record risks cross-meeting writes. Global rollback of refinement fields can erase unrelated edits.
- **Rationale/tradeoffs:** Existing domain owners can retain work without a generic job framework or data migration. Meetings can progress independently, with bounded insight concurrency and scoped refinement-write recovery. Explicit Stop/deletion still rejects providers that ignore cancellation. Users must leave the app running for unfinished requests.
- **Impact and validation:** Supersedes selection/lifecycle cancellation and cross-meeting manual replacement in [DEC-20260905-008](#dec-20260905-008), [DEC-20260905-016](#dec-20260905-016), [DEC-20260905-017](#dec-20260905-017), and [DEC-20260904-002](#dec-20260904-002); other contracts remain adopted. Tests verify switching/return, two independent refinement owners, background saves/titles, retry, partial batches, deletion with ignored cancellation, shared insight capacity, independent Stop, summary queueing, and scoped save failure. Native renders verify background activity at 940×480 and 1120×760. See [Phase 2 validation](phase-2-validation.md).
- **Files:** `Sources/Insights/MeetingRefinementController.swift`, `Sources/Insights/TranscriptRefiner.swift`, `Sources/Insights/InsightEngine.swift`, `Sources/Meeting/CaptureCoordinator.swift`, `Sources/History/MeetingHistory.swift`, `Sources/App/MeetingStage.swift`, `Sources/App/MeetingSidebar.swift`, `Sources/App/InsightInspector.swift`, related tests.

---

<a id="dec-20260906-008"></a>
## DEC-20260906-008: Let the AI settings draft own asynchronous service checks

- **Date:** 2026-09-06
- **Status:** Accepted
- **Scope:** AI settings state ownership and request lifetime
- **Context:** Settings retains editable preferences across tab switches and dismissal. Keeping connection tests and model discovery in the view split their lifetime from the draft: old replies could validate changed credentials, and dismissed discovery could leave a retained view loading indefinitely. SwiftUI can retain dismissed native sheets without immediately calling onDisappear.
- **Decision:** AISettingsDraft owns both checks, their task handles, cancellation tokens, discovered models, and progress/errors. Changing provider/key/address invalidates checks and discovered models; a model edit invalidates the connection test. The Settings presentation boundary cancels checks on dismissal and clears active loading while preserving editable values. Responses must match their request token and pass cancellation checks. Discovery may select a returned model only if the model field is unchanged since dispatch. Vocabulary extraction remains owned by its editor and continues independently.
- **Rejected alternatives:** View-local tasks retain split ownership. Comparing only field values permits an old request to become current after editing away and back. Clearing the whole draft on dismissal loses intentional edits. Cancelling all AI work when Settings closes would incorrectly stop vocabulary extraction.
- **Rationale/tradeoffs:** A draft has one testable owner for preferences and their validation, without adding another coordinator or generic request framework. Closing Settings deliberately abandons its diagnostic checks; reopening can run fresh checks with retained values. Save/Cancel and persisted configuration remain unchanged.
- **Impact and validation:** Controlled-provider tests cover ignored cancellation, changed credentials, invalid responses, discovery retry after dismissal, and manual model edits. A native Settings-sheet test verifies cancellation through the presentation boundary. The full SameWave suite passed 176/176 on macOS arm64; see [Phase 2 validation](phase-2-validation.md).
- **Files:** `Sources/AI/AISettingsDraft.swift`, `Sources/AI/AISettingsView.swift`, `Sources/App/SettingsView.swift`, `Tests/AISettingsDraftTests.swift`, `Tests/SettingsPresentationTests.swift`.

---

<a id="dec-20260906-007"></a>
## DEC-20260906-007: Virtualize uniform vocabulary rows within stable cards

- **Date:** 2026-09-06
- **Status:** Accepted
- **Scope:** Shared vocabulary rendering, Settings tab performance, and scroll geometry
- **Context:** Settings tab changes visibly stalled with more than 200 saved terms. A native 300-term fixture measured a median update/layout pulse of 109 ms. Removing the vocabulary subtree's enabled-state toggle improved only part of the cost; separating the list's observation boundary removed repeated data reads but still left roughly 75 ms of layout work.
- **Decision:** Keep the Settings presentation from [DEC-20260906-006](#dec-20260906-006) and the shared editor. Use separate view bodies for saved terms and suggestions, and LazyVStack only for their term rows. Keep cards and the single outer ScrollView eager. Saved rows have a stable 32-point height with two-line display text; candidate rows are 36 points. Each saved term has one row view. Show invalid-input feedback within the saved row, with the full reason available through its tooltip and accessibility label, so validation never changes row height. Gate hidden-tab hit testing, accessibility, focus, and keyboard actions without disabling the entire vocabulary subtree.
- **Rejected alternatives:** Eagerly creating every term retains work proportional to the full vocabulary during tab changes. View extraction alone does not bound layout work. Making whole cards lazy reintroduces uncertain card-height estimates. Variable-height validation outside a lazy row left an incorrect document extent after cancelling edits in the native regression test. Replacing the shared editor with a separate native list host would add unnecessary UI and lifecycle machinery.
- **Rationale/tradeoffs:** Uniform term rows suit on-demand rendering while the surrounding cards retain exact geometry. This preserves the existing interaction and reading position without creating hundreds of offscreen controls. The compact inline error replaces a below-row error line. Pending text, selected suggestions, file inputs, extraction, and explicit commit rules retain their existing owners.
- **Validation:** XcodeGen and unsigned Debug passed. Full SameWave XCTest passed 162/162 on macOS arm64. On the same machine, the 300-term fixture's median tab update/layout pulse fell to 13 ms, with zero saved-term reads across eight switches. These are hosted Debug measurements, not a universal frame-rate guarantee. Regression tests cover 300 mixed-length terms, distant scrolling, invalid edits, cancellation, tab switching, and unchanged extent/offset, plus existing suggestion arrival/reopen/focus tests. See [Phase 2 validation](phase-2-validation.md).
- **Files:** `Sources/App/SettingsView.swift`, `Sources/Capture/VocabularyEditorView.swift`, `Tests/VocabularyPerformanceTests.swift`, `Tests/MainViewRenderingTests.swift`.

---

<a id="dec-20260906-006"></a>
## DEC-20260906-006: Embed personal vocabulary directly in Settings

- **Date:** 2026-09-06
- **Status:** Accepted
- **Scope:** Personal vocabulary presentation and navigation within Settings
- **Replaces:** The independent personal window and Settings handoff in [DEC-20260906-005](#dec-20260906-005). Its shared editing, scope ownership, commit, and lifecycle decisions remain adopted.
- **Context:** The user first requested a native panel instead of an independent window, then refined the requirement to embed vocabulary management within Settings itself. A second presentation layer adds an unnecessary step between choosing Vocabulary and editing terms.
- **Decision:** Render VocabularyEditorView directly in Settings' Vocabulary tab. Remove the count/Manage landing page and independent window scene and wrapper. Keep the same 600×540 Settings sheet and visible AI Services/Vocabulary selector. Use a compact Personal Vocabulary scope heading within the scroll content and one fixed Done footer. Configure AI Services selects the adjacent tab in the same presenter. Pending AI preferences are identified in the vocabulary footer; only AI Save commits them.
- **State:** Both Settings tab views remain mounted, preserving local UI and reading state. Vocabulary keyboard focus is active only in its visible tab and restores on return. App-owned drafts, temporary files, suggestions, selections, and extraction survive tab switches and Settings dismissal. Explicit Add, row Save, Remove, and selected suggestion saves remain separate from AI Save/Cancel. No storage or provider change is needed.
- **Rejected alternatives:** A second sheet or navigation detail retains the redundant Manage step. An independent vocabulary window conflicts with the latest requirement. Replacing the shared editor with a separate Settings implementation duplicates interaction and commit rules. Resizing the Settings sheet for each tab destabilizes navigation.
- **Rationale/tradeoffs:** Direct editing gives the two tabs one predictable presentation and preserves the approved vocabulary cards. Settings occupies its presenter while open; Done releases it while background extraction continues. The fixed height makes long lists scroll, with review actions still owned by Suggested Terms.
- **Validation:** XcodeGen and unsigned Debug build passed. Full SameWave XCTest passed 160/160 on macOS arm64. Native tests verify one Settings sheet, stable dimensions, independent drafts/commits, Configure AI routing, focus restoration, Escape dismissal, continued extraction after closure, and 100-term scrolling across tab changes and reopen. Native render checks cover direct editing and Suggested Terms. See [Phase 2 validation](phase-2-validation.md).
- **Files:** `Sources/App/SettingsView.swift`, `Sources/App/SameWaveApp.swift`, `Sources/Capture/VocabularyEditorView.swift`, `Tests/SettingsPresentationTests.swift`, `Tests/VocabularyImportControllerTests.swift`, `Tests/MainViewRenderingTests.swift`.

---

<a id="dec-20260906-005"></a>
## DEC-20260906-005: Separate Context and share explicit vocabulary editing across scopes

- **Date:** 2026-09-06
- **Status:** Superseded for personal vocabulary presentation by [DEC-20260906-006](#dec-20260906-006); Context ownership, shared editing, explicit commits, and app-session state remain accepted.
- **Scope:** Preparation ownership, personal/meeting vocabulary interaction, app-session state, and settings handoff
- **Replaces:** The merged document/term presentation and global review footer in [DEC-20260906-004](#dec-20260906-004), the personal bulk-draft/import bridge and close-to-cancel policy in [DEC-20260905-001](#dec-20260905-001), and the affected Settings/Preparation behavior in [DEC-20260906-001](#dec-20260906-001) and [DEC-20260905-012](#dec-20260905-012).
- **Context:** The user wants Context to own Markdown, Vocabulary to support manual entry and extraction, and Settings to reuse the approved native editor. Selection state and review actions belong to Suggested Terms. Personal work must remain nonmodal, and closing either host should preserve progress.
- **Decision:** Keep Context and Vocabulary as separate Preparation cards. One VocabularyEditorView supports multiline Add Terms, row Save/Cancel, Remove, and selected suggestion saves in both scopes. Each action commits explicitly; manual and AI preference drafts remain independent. Suggested Terms contains selection, Add, Discard, validation, and save feedback, with repeated controls at both ends of long cards. Done only dismisses. Meeting editing references Context's document count and returns to that card for changes. Personal editing chooses temporary local files in its own window; Extract is a separate transmission action. No document previews, source metadata, request details, or Review destination are added.
- **State and persistence:** AppDelegate owns the personal VocabularyEditorStore; CaptureCoordinator caches one per meeting. Dismissal preserves app-session drafts, suggestions, file selection, reading position, and extraction. Stop retains results; Discard clears pending review/progress only when stopped. Retry uses the original request inputs/provider. Meeting deletion invalidates the owner and rejects late results. Saved vocabulary remains in its existing distinct stores; temporary files and unfinished work end at app exit. AISettingsDraft belongs to SettingsNavigation and survives personal-window handoff; AI Save/Cancel never writes vocabulary. Scoped SwiftData undo restores a failed vocabulary operation without reverting unrelated pending edits or manually reinserting deleted models.
- **Rejected alternatives:** Duplicate meeting document lists obscure ownership. A global document library exceeds the personal-import requirement. Keeping bulk Settings Save/Cancel around vocabulary perpetuates two commit models. Closing to discard disrupts task switching. Separate Review tabs, nested list scrollers, and global review footers separate actions from their data. New extraction scheduling or a generic host framework is unnecessary.
- **Rationale/tradeoffs:** The same native 600×540 editor works in a meeting sheet and a nonmodal personal window, with a small source-area difference. Long lists require scrolling between in-card toolbars; stable rows and restored offsets preserve reading. Explicit vocabulary commits cannot be undone by cancelling AI settings. Invalid selected suggestions block Add; unchecked invalid rows do not. Existing serial batching, limits, retries, and privacy boundaries remain intact.
- **Validation:** XcodeGen and unsigned Debug passed. Full XCTest: 159 passed, 0 failed, 0 skipped on SameWave / macOS arm64. Tests cover local-only selection, manual add/edit/remove, duplicate and invalid input, independent drafts, progressive selected saves, native close/reopen, scroll restoration, repeated save failures followed by retry, scoped undo, database reopen, deletion, and late responses. Native 600×540 renders verify both hosts and in-card controls. See [Phase 2 validation](phase-2-validation.md).
- **Files:** `Sources/Capture/VocabularyEditorStore.swift`, `Sources/Capture/VocabularyEditorView.swift`, `Sources/Meeting/MeetingContextView.swift`, `Sources/Meeting/MeetingPreparationView.swift`, `Sources/History/MeetingWorkspace.swift`, `Sources/AI/AISettingsDraft.swift`, `Sources/App/SettingsView.swift`, corresponding vocabulary and native presentation tests.

---

<a id="dec-20260906-004"></a>
## DEC-20260906-004: Keep meeting vocabulary extraction in one continuous sheet

- **Date:** 2026-09-06
- **Status:** Superseded by [DEC-20260906-005](#dec-20260906-005) for Context ownership, shared editing, and in-card review actions.
- **Scope:** Meeting Preparation vocabulary management and confirmation flow
- **Replaces:** The separate Review destination and reopening navigation in [DEC-20260906-001](#dec-20260906-001). Its ownership, cancellation, and Settings decisions remain adopted.
- **Context:** A permanent Review tab separates extraction from its results and obscures where selected terms are saved. OpenDesign evaluated a focused native sheet with documents, suggestions, and saved terms in reading order.
- **Decision:** Remove the management tabs. Keep Documents and Meeting Vocabulary in one scroll area, with a temporary Suggested Terms group directly below extraction. Editable checkboxes and an explicit Not saved label distinguish suggestions from saved rows. Keep Add to Vocabulary and Done in the fixed footer. Adding saves only the selection and leaves unchecked suggestions in place, even while extraction continues; Done only dismisses. Progress, Stop, incomplete-only retry, and errors remain inline. Use stable row identities without automatic navigation or scrolling on incoming results. Manual entry opens inline.
- **Rejected alternatives:** Renaming Review leaves the disconnection. A wizard or nested review modal adds navigation and blocks document/term management. Saving generated terms automatically removes the user's spelling/selection decision.
- **Rationale/tradeoffs:** Extraction, confirmation, and the saved destination remain visible together for typical lists. Longer lists scroll within the same sheet, while actions remain available. The existing meeting-owned importer retains work across closure; no new workflow persistence or network policy is introduced. Personal Markdown import retains its independent window.
- **Impact and validation:** Full XCTest passed 154/154. Native renders cover empty, three-suggestion, running, save-failure, selected-only save, no-new-terms, and long-list states. Controlled providers verify edits, unchecked retention, saving during generation, closure, retry, and deletion. See [Phase 2 validation](phase-2-validation.md).
- **Files:** `Sources/Meeting/MeetingVocabularyView.swift`, `Sources/Meeting/MeetingPreparationView.swift`, `Sources/Capture/VocabularyImportController.swift`, `Tests/MainViewRenderingTests.swift`, `Tests/VocabularyImportControllerTests.swift`.

---

<a id="dec-20260906-003"></a>
## DEC-20260906-003: Present compact vocabulary progress without request details

- **Date:** 2026-09-06
- **Status:** Accepted
- **Scope:** Vocabulary diagnostics, progress state, and error presentation
- **Replaces:** Request-history and timing presentation in [DEC-20260905-001](#dec-20260905-001).
- **Context:** The user wants Request Details removed from Markdown vocabulary extraction in both workflows.
- **Decision:** Remove the shared details rows, attempt-history collection, timestamps, and duration measurement. Retain the current attempt for compact progress and batch statuses for incomplete-only retry. Show preparation errors or the latest exhausted batch error inline. Retry clears errors for retried batches; Stop and completion clear current progress.
- **Rejected alternatives:** Keeping invisible timing/history retains unused state. Removing the details panel without another error surface hides the provider failure reason.
- **Rationale/tradeoffs:** Review focuses on terms and essential controls. Per-attempt diagnostics are no longer available; partial results, error feedback, cancellation, and retry remain supported.
- **Impact and validation:** Full XCTest passed 152/152. Controlled providers verify retry inputs, preserved edits/selections, current-attempt cleanup, and failure feedback through recovery. Native review capture confirms the panel is absent. See [Phase 2 validation](phase-2-validation.md).
- **Files:** `Sources/Insights/VocabularyGenerator.swift`, `Sources/Capture/VocabularyImportController.swift`, `Sources/Capture/VocabularyImportWindow.swift`, `Sources/Meeting/MeetingVocabularyView.swift`, `Tests/VocabularyGeneratorTests.swift`, `Tests/VocabularyImportControllerTests.swift`.

---

<a id="dec-20260906-002"></a>
## DEC-20260906-002: Keep extracted vocabulary as term strings only

- **Date:** 2026-09-06
- **Status:** Accepted
- **Scope:** Personal and meeting vocabulary review, processing, and persisted term data
- **Replaces:** Per-term source collection, disclosure, and retention in [DEC-20260905-001](#dec-20260905-001), [DEC-20260905-007](#dec-20260905-007), [DEC-20260905-012](#dec-20260905-012), and [DEC-20260906-001](#dec-20260906-001). Their unrelated lifecycle and ownership decisions remain adopted.
- **Context:** The user no longer needs source metadata when extracting vocabulary from Markdown. The AI contract already returns only phrase strings; the application had been matching and copying local excerpts separately.
- **Decision:** Remove local excerpt matching, redundant fragment copies, candidate source collections, saved term provenance, and Source disclosures from both workflows. Keep the existing phrase-only prompt and schema. Documents remain independent extraction inputs; confirmed spellings survive attachment removal. Review retains stable IDs, original extraction identity, editable text, selection, progressive save, and incomplete-request retry.
- **Rejected alternatives:** Hiding Source while retaining collection or persistence leaves unused work and duplicated document content. Adding an optional provenance setting or compatibility reader preserves a removed path.
- **Rationale/tradeoffs:** Term-only data serves recognition and the requested compact review without retaining excerpts for an unused feature. Vocabulary entries no longer provide passage attribution. Meeting attachments retain their existing explicit lifecycle.
- **Impact and validation:** Removed the provenance model field without adding migration or compatibility code. Full XCTest passed 152/152, including actual request content/Unicode preservation, edits and selections across duplicate batches, partial saves/retries, attachment removal during extraction, on-disk term reopen, isolation, and cancellation. The native review capture contains only term rows and selection controls. See [Phase 2 validation](phase-2-validation.md).
- **Files:** `Sources/Insights/VocabularyGenerator.swift`, `Sources/Capture/VocabularyImportController.swift`, `Sources/Capture/VocabularyImportWindow.swift`, `Sources/History/MeetingWorkspace.swift`, `Sources/Meeting/MeetingVocabularyView.swift`, `Tests/VocabularyGeneratorTests.swift`, `Tests/VocabularyImportControllerTests.swift`, `Tests/MeetingWorkspaceTests.swift`.

---

<a id="dec-20260906-001"></a>
## DEC-20260906-001: Separate Settings presentation from meeting vocabulary work

- **Date:** 2026-09-06
- **Status:** Superseded for vocabulary interaction and Settings draft lifetime by [DEC-20260906-005](#dec-20260906-005), source metadata by [DEC-20260906-002](#dec-20260906-002), and Review navigation by [DEC-20260906-004](#dec-20260906-004); other decisions remain accepted.
- **Scope:** Settings presentation, meeting extraction lifetime, and attachment removal
- **Replaces:** The management-sheet cancellation policy in [DEC-20260905-012](#dec-20260905-012). The personal Markdown import window retains its independent close-to-cancel behavior.
- **Context:** The user prefers Preparation's native sheets for settings, needs personal Markdown analysis to remain nonblocking, and reported inaccessible attachment removal and uncertain behavior when closing meeting vocabulary extraction.
- **Decision:** Present Settings as a native sheet from the app menu, Command-comma, and configuration links, using the currently visible main/preparation window. Save commits the active tab and dismisses; Cancel reverts that tab and dismisses. Starting or resuming personal Markdown import opens its existing independent window and dismisses Settings. The capture coordinator retains one vocabulary importer per meeting for the app session. Closing management or switching meetings keeps requests, progress, candidate edits, and selection. Reopening enters active review; Preparation shows progress or waiting review. Explicit Stop retains review; Discard clears it. Successful meeting deletion cancels and releases work; generation tokens reject late results. Attachment rows provide direct removal without content preview. Removing attachments never changes current extraction's immutable document input or retained term provenance; it affects future extraction.
- **Rejected alternatives:** Cancelling on sheet disappearance discards useful work and couples tasks to incidental presentation changes. A separate Settings window conflicts with the requested interaction. Making Markdown analysis a child settings sheet blocks the workspace. Disabling attachment removal during extraction is unnecessary because request inputs already copy document values. Persisting unfinished network jobs or unconfirmed review introduces a recovery mechanism beyond the current requirement.
- **Rationale/tradeoffs:** Keep provider/parser/review behavior shared while giving each workflow an explicit owner and cancellation boundary. Unconfirmed review lasts until app exit, with an inline reminder to save. Settings routing uses weak native window references and actual visibility because macOS can retain dismissed sheet content without immediately calling SwiftUI onDisappear.
- **Impact and validation:** Native window tests cover root/nested Settings presentation and reopening after a retained sheet closes. Controlled-provider tests cover panel closure, edited/unchecked candidates, attachment removal during generation, meeting isolation, retained source excerpts, deletion, and ignored late replies. Existing personal-window hide/close tests remain applicable. See [Phase 2 validation](phase-2-validation.md).
- **Files:** `Sources/App/SettingsView.swift`, `Sources/App/SameWaveApp.swift`, `Sources/Meeting/CaptureCoordinator.swift`, `Sources/Meeting/MeetingVocabularyView.swift`, `Sources/Meeting/MeetingPreparationView.swift`, `Sources/History/MeetingWorkspace.swift`, `Tests/SettingsPresentationTests.swift`, `Tests/VocabularyImportControllerTests.swift`.

---

<a id="dec-20260905-017"></a>
## DEC-20260905-017: Run custom insight batches with bounded parallelism

- **Date:** 2026-09-05
- **Status:** Superseded for AI task lifetime and cross-meeting replacement by [DEC-20260906-009](#dec-20260906-009). The shared concurrency cap and other contracts remain accepted.
- **Scope:** Insight request concurrency and batch completion
- **Replaces:** Serial batch dispatch in [DEC-20260905-016](#dec-20260905-016) and the single manual slot as a batch constraint in [DEC-20260905-008](#dec-20260905-008). Frozen inputs/provider, independent history, and cancellation behavior remain adopted.
- **Context:** The user wants independent insight requests to run concurrently, with a maximum of six to eight, instead of waiting for each preceding result.
- **Decision:** Set a fixed cap of six active insight requests, counting automatic work. Dispatch batch items in reading order until capacity is filled, then refill after any completion, failure, or individual stop. Keep a batch active until its queue and active requests are both empty. Save out-of-order results independently under their owning definitions. Clear batch identity and pending work before cancelling active requests so Stop cannot launch additional work. Retain the one-automatic-request policy and existing standalone manual replacement behavior.
- **Rejected alternatives:** Keeping serial dispatch adds unnecessary wait between independent requests. Unbounded dispatch ignores the requested cap. Reserving an extra automatic slot outside the cap exceeds the stated maximum. Finishing the batch when the queue becomes empty hides active requests and releases the frozen provider too early.
- **Rationale/tradeoffs:** Six is within the user's requested range and needs no additional configuration. Bounded parallelism reduces wait for independent results while maintaining an explicit concurrency limit. It does not reduce the number or size of provider requests, and response order is intentionally independent of card order.
- **Impact and validation:** Held-provider tests verify the six-request peak, initial reading-order selection, immediate refill, out-of-order history, provider freezing for queued work, shared automatic capacity, failed/deleted items, and cancellation without late writes. Native rendering shows multiple generating cards and queued state. See [Phase 2 validation](phase-2-validation.md).
- **Files:** `Sources/Insights/InsightEngine.swift`, `Tests/InsightBatchTests.swift`, `Tests/Phase2TestSupport.swift`, `Tests/MainViewRenderingTests.swift`.

---

<a id="dec-20260905-016"></a>
## DEC-20260905-016: Queue explicit custom insight batches through the manual slot

- **Date:** 2026-09-05
- **Status:** Superseded for AI task lifetime and cross-meeting replacement by [DEC-20260906-009](#dec-20260906-009). Superseded by [DEC-20260905-017](#dec-20260905-017) for serial dispatch; grouping, frozen requests/provider, history, and cancellation retained.
- **Scope:** Custom insight presentation and manual generation scheduling
- **Context:** The user requested a Custom Insights heading with one Generate action for all editable insights, alongside the existing Meeting Insights controls. Calling the previous single-item action repeatedly would cancel every request except the last.
- **Decision:** Group editable definitions, including the editable Overview preset, under Custom Insights. Generate freezes their reading order, configurations, original source cutoff, provisional text, vocabulary, provider, model label, and request time, then dispatches one item at a time through the existing manual slot. Exclude the independent meeting-wide summary. Retain per-card history and actions, show queued status, and offer Stop for the batch or an individual item. Save each success independently and continue after individual preflight, provider, or save failures. Block a new batch until included unsaved results are saved. Repeated clicks coalesce; lifecycle cancellation and replacement manual requests discard pending work and reject late results.
- **Rejected alternatives:** Unbounded parallel requests remove the established manual concurrency limit. Repeated calls to the old single-item action cancel peer requests. Combining all definitions into one model response couples independent prompts, errors, and history. Reading inputs or selecting providers when each queued item starts would mix cutoffs or mislabel results after edits.
- **Rationale/tradeoffs:** A serial batch preserves independent insight semantics and bounded request concurrency at the cost of waiting for earlier items. It is transient work, not a persisted job queue; app relaunch retains saved results but does not resume unfinished requests. Meeting-wide summary generation remains explicit and separate.
- **Impact and validation:** Controlled-provider tests verify ordered dispatch, frozen inputs/provider selection, automatic exclusion of queued items, failure continuation, save retry, stop, manual replacement, deleted definitions, and cancellation on meeting switch. Native rendering covers the section header and queued/generating cards at narrow width; the scrolling regression remains passing. See [Phase 2 validation](phase-2-validation.md).
- **Files:** `Sources/Insights/InsightEngine.swift`, `Sources/Meeting/CaptureCoordinator.swift`, `Sources/App/InsightInspector.swift`, `Sources/Insights/InsightResultCard.swift`, `Tests/InsightBatchTests.swift`, `Tests/MainViewRenderingTests.swift`.

---

<a id="dec-20260905-015"></a>
## DEC-20260905-015: Remove insight Details and generated supporting quotes

- **Date:** 2026-09-05
- **Status:** Accepted
- **Scope:** Insight presentation, generated response contract, and export
- **Replaces:** Details access in [DEC-20260905-014](#dec-20260905-014) and its predecessors, and the generated evidence-quote requirement in [DEC-20260905-009](#dec-20260905-009). Full original input, custom priority, named summary cards, and immutable history remain adopted.
- **Context:** The user no longer wants Details for custom insights or the app's meeting summaries and authorized removing the associated information requests.
- **Decision:** Remove the Details sheet and every saved, archived, and unsaved result entry point. Remove supporting-quote instructions, the evidence response field/schema/type, quote validation/export, and unused source/vocabulary fingerprints. The response now requires only conclusion, points, and nullable summary; unexpected top-level fields fail validation. Read all custom points and meeting sections directly on their cards, including unsaved results with Retry Save. Preserve shared history menus and export every saved result version.
- **Rejected alternatives:** Hiding the button while continuing to request unused citations adds output cost and dead code. Removing the original transcript input would change the analysis itself. Clearing stored snapshots would discard history unrelated to this presentation request.
- **Rationale/tradeoffs:** Keep the response focused on result content and retain the existing generation/persistence pipeline. Original-source grounding, provisional uncertainty, and factual constraints remain in prompts; structural and content-bound validation remains in the client. The app no longer offers generated citation inspection. Export retains the overall summary conclusion without restoring a Details surface.
- **Impact and validation:** Schema/parser tests cover the reduced response, missing/invalid/extra fields, and persisted output. Native screenshot text checks cover custom and meeting results, archive, generation failures, and unsaved content without Details. Full validation and signed desktop delivery are recorded in [Phase 2 validation](phase-2-validation.md).
- **Files:** `Sources/Insights/InsightModels.swift`, `Sources/Insights/InsightEngine.swift`, `Sources/Insights/InsightResultCard.swift`, `Sources/History/TranscriptExporter.swift`, `Tests/InsightEngineTests.swift`, `Tests/OpenAICompatibleProviderTests.swift`, `Tests/MainViewRenderingTests.swift`. Removed `Sources/Insights/InsightCards.swift`.

---

<a id="dec-20260905-014"></a>
## DEC-20260905-014: Make the named sections the primary summary cards

- **Date:** 2026-09-05
- **Status:** Superseded by [DEC-20260905-015](#dec-20260905-015) for Details access; primary section cards, shared history, and failure-state behavior retained.
- **Scope:** Summary presentation and missing-result states
- **Replaces:** The enclosing conclusion card in [DEC-20260905-013](#dec-20260905-013). Its shared result contract, custom priority, immutable versions, and explicit generation remain adopted.
- **Context:** Appending sections below a Full Meeting Summary card still foregrounded the summary wrapper, and displayed no sections before generation. The user explicitly wants the topics, suggestions, actions, and decisions to be the cards themselves.
- **Decision:** Render Topics, Suggestions, Action Items, Decisions, and Open Questions directly, under compact shared generation/history controls. Remove the enclosing title/conclusion card for structured results. Keep the overall conclusion in Details and export. Meeting-wide sections appear with honest missing-content placeholders before generation and remain visible during generation, failure, and cancellation. Unsaved sections retain Retry Save and previous saved versions remain available.
- **Rejected alternatives:** Renaming the old card alone leaves the same hierarchy. Creating one request/history per part gives related sections different evidence cutoffs. Filling missing sections by parsing existing prose invents structure that the provider did not return.
- **Rationale/tradeoffs:** Keep the shared engine, schema, storage, and history while making the requested categories the primary reading surface. Missing content is distinct from a generated conclusion that nothing was recorded. The initial overview remains an editable definition; its structured results use this same presentation.
- **Impact and validation:** Native rendering covers empty, generating, failed, cancelled, unsaved, and populated sections at 216-point width. Local Vision text recognition over rendered test images asserts that the named parts are visible and the obsolete summary title/conclusion card is absent. This catches a missing empty-state surface that populated fixtures alone missed. Full validation and desktop delivery are recorded in [Phase 2 validation](phase-2-validation.md).
- **Files:** `Sources/Insights/InsightResultCard.swift`, `Sources/Insights/MeetingSummaryCards.swift`, `Sources/Insights/MeetingSummary.swift`, `Sources/History/MeetingWorkspace.swift`, `Tests/MainViewRenderingTests.swift`, `Tests/TranscriptExporterTests.swift`.

---

<a id="dec-20260905-013"></a>
## DEC-20260905-013: Prioritize custom insights and show multipart summaries inline

- **Date:** 2026-09-05
- **Status:** Superseded by [DEC-20260905-014](#dec-20260905-014) for the enclosing conclusion card; result contract, custom priority, immutable history, and explicit generation retained.
- **Scope:** Insight result contract, reading order, live overview and full-summary presentation
- **Replaces:** [DEC-20260905-012](#dec-20260905-012) for reading order, initial expansion, and the summary sheet. Its preparation, evidence disclosure, independent history, decorative colors, and existing-shell boundaries remain adopted.
- **Context:** The user wants custom insights above the default overview and both live and post-meeting summaries visible as multiple parts without opening or expanding them. A flat summary in a separate sheet hides useful meeting context.
- **Decision:** Show definitions in reverse creation order, putting new user definitions above the initial editable Overview, and show Full Meeting Summary last after End. Keep titles editable and use no default/custom type flag. Extend the shared result with a nullable structured summary containing topics, decisions, action items, open questions, and suggestions. Broad overview prompts request these parts; focused prompts use points and a null summary. Full-summary responses must contain the parts. All parts share one immutable request, cutoff, and history selection. Render the conclusion and parts directly in the inspector with the approved pastel cards; ordinary conclusions and points also start expanded.
- **Retained behavior:** Full summary generation remains explicit after End. Evidence and exact inputs remain in Details. Preparation keeps three cards and management/editing sheets. Saved versions, unsaved retry, palette identities, and the native three-column shell remain intact.
- **Rejected alternatives:** A separate summary engine duplicates generation and history. Parsing headings from prose loses a validated structural contract. Matching an editable title to choose priority breaks on rename or duplicate titles. Splitting parts into independent generations makes their cutoffs and versions disagree. A default/custom model flag adds state unnecessary for the current single editable preset.
- **Rationale/tradeoffs:** A typed optional part structure extends the existing provider, snapshot, and export path without migrations or a second schema pipeline. Empty arrays make absent facts explicit; suggestions remain proposals and unknown owners/dates stay unknown. Reverse creation order also places newer custom definitions above older ones. Broad-versus-focused live formatting follows analytical prompt intent; full summaries additionally enforce the structured payload at validation.
- **Impact and validation:** Structured parts persist and export with their parent result. Tests cover the shared live/full response structure, explicit null, missing/invalid/oversized parts, duplicate flat content, immutable snapshots, empty-part exports, custom priority after rename/deletion, and stable colors. Native render fixtures verify expanded live/full cards at 256/216-point content widths. Complete validation and desktop delivery are recorded in [Phase 2 validation](phase-2-validation.md).
- **Files:** `Sources/Insights/InsightModels.swift`, `Sources/Insights/MeetingSummary.swift`, `Sources/Insights/MeetingSummaryCards.swift`, `Sources/Insights/InsightResultCard.swift`, `Sources/Insights/InsightPresentation.swift`, `Sources/App/InsightInspector.swift`, `Sources/History/TranscriptExporter.swift`, `Tests/MeetingSummaryTests.swift`, `Tests/InsightPresentationTests.swift`, `Tests/MainViewRenderingTests.swift`.

---

<a id="dec-20260905-012"></a>
## DEC-20260905-012: Present insights as peer cards with progressive disclosure

- **Date:** 2026-09-05
- **Status:** Superseded by [DEC-20260905-013](#dec-20260905-013) for insight presentation, [DEC-20260906-001](#dec-20260906-001) for vocabulary closure, [DEC-20260906-002](#dec-20260906-002) for source metadata, and [DEC-20260906-005](#dec-20260906-005) for Preparation and shared vocabulary editing; independent history, decorative colors, and shell boundaries retained.
- **Scope:** Insight reading, preparation, and presentation state
- **Context:** The Phase 2 item picker hid other insights, inline evidence dominated results, and preparation exposed too much configuration. The user approved OpenDesign's colored C cards and three-card preparation while explicitly retaining the existing native shell.
- **Decision:** Show Meeting Overview and user definitions together in creation order. Each card owns its selected version and conclusion/point expansion. Latest follows arrivals; an explicitly chosen version stays selected, with a newer-result notice. Details freezes the selected saved value and exposes evidence, original inputs, prompt, vocabulary, and metadata. Keep failures and unsaved-save retry with the owning item. Use a deliberate summary sheet from the inspector footer, and retain removed-definition history under Preparation.
- **Preparation:** Show Meeting title, Vocabulary & context, and AI Insights cards. Move document import, extraction/review, terms, and provenance to a management sheet, and prompt/focus/automatic settings to a definition editor. Closing management cancels unsaved extraction work; it does not remove confirmed terms.
- **Rejected alternatives:** Separate default/custom tabs imply different data types and hide related results. A single global timeline couples unrelated reading choices. Inline evidence overloads the primary reading view. A shell redesign exceeds the requested scope.
- **Rationale/tradeoffs:** Reuse the existing engine and immutable result model, with stable SwiftUI card identities. Decorative color slots are allocated by definition ID for the window session and do not introduce persisted type flags or user color settings. Full configuration and evidence remain one action away; short windows scroll content while sheet actions remain available.
- **Impact and validation:** The three-column layout, sidebar, titlebar, caption hierarchy, control capsule, and resize behavior remain unchanged. Targeted XCTest covers independent reading state, palette identity through deletion/reorder/addition, archived versions, and native rendering at 1120×760 and 940×480. Full build/test and desktop-delivery evidence is recorded in [Phase 2 validation](phase-2-validation.md).
- **Files:** `Sources/App/InsightInspector.swift`, `Sources/Insights/InsightResultCard.swift`, `Sources/Insights/InsightCards.swift`, `Sources/Insights/InsightPresentation.swift`, `Sources/Meeting/MeetingPreparationView.swift`, `Sources/Meeting/MeetingVocabularyView.swift`, `Sources/Meeting/InsightDefinitionEditor.swift`, `Tests/InsightPresentationTests.swift`, `Tests/MainViewRenderingTests.swift`.

---

<a id="dec-20260905-011"></a>
## DEC-20260905-011: Keep selection on a stored meeting while any remain

- **Date:** 2026-09-05
- **Status:** Accepted
- **Scope:** Deletion, startup selection, empty-state presentation
- **Replaces:** Missing/deleted-selection behavior in [DEC-20260905-004](#dec-20260905-004). Persistent draft ownership from [DEC-20260905-007](#dec-20260905-007) remains.
- **Context:** Deleting preparation previously selected a synthetic New Meeting row even when saved meetings remained. This implied a new workspace that did not exist.
- **Decision:** Preserve selection when deleting another meeting. After deleting the displayed meeting, select a remaining mounted meeting or the most recently created stored meeting, matching sidebar order. Restore its draft/history/paused state without starting capture, and persist the UUID immediately. Apply the same newest-record choice when startup has no valid saved UUID. With an empty store, clear retained transcript state and show an explicit empty state; only New Meeting creates a draft.
- **Rejected alternatives:** An implicit new draft creates unwanted data after deletion. A synthetic New Meeting row misrepresents persistence. Choosing a paused meeting before newer history imposes a lifecycle priority absent from sidebar order.
- **Rationale/tradeoffs:** Existing content remains available with a predictable successor and no new preference or database field. A most-recent-created successor may differ from the last-viewed remaining meeting; the app does not introduce a second recency history.
- **Impact and validation:** Sixteen selection tests pass, including draft/history/paused successors, invalid/missing UUIDs, nonselected deletion, last-record deletion, retained transcript cleanup, and reopening. Views remove the synthetic row and empty-state capture dock.
- **Files:** `Sources/Meeting/CaptureCoordinator.swift`, `Sources/History/MeetingHistory.swift`, `Sources/App/MeetingSidebar.swift`, `Sources/App/MeetingStage.swift`, `Tests/MeetingSelectionTests.swift`.

---

<a id="dec-20260905-010"></a>
## DEC-20260905-010: Isolate hosted tests from personal meetings and capture permissions

- **Date:** 2026-09-05
- **Status:** Accepted
- **Scope:** Validation workflow and test-host persistence/permission boundaries
- **Context:** Hosted XCTest previously ran normal app startup, opening personal history and requesting permissions before the domain tests. Repeated schema/lifecycle validation must not operate on the user's active meeting data.
- **Decision:** Detect the existing `XCTestBundlePath` boundary in app assembly. Use an explicitly in-memory history container and skip personal selection restoration and speech/microphone preflight. Domain tests supply isolated defaults, stores, and provider fixtures. Production startup still uses its persistent store and normal permission flow.
- **Rejected alternatives:** Running every domain test through normal personal startup creates unrelated persistent side effects; adding a production fallback database would hide real failures.
- **Rationale/tradeoffs:** Reuse the existing test-key isolation signal without a new runtime setting. Signed-app capture remains a separate smoke-test responsibility.
- **Impact and validation:** `AppIdentityTests` asserts the host uses memory storage and has not restored a personal selection; full validation is recorded in [Phase 2 validation](phase-2-validation.md).
- **Files:** `Sources/App/SameWaveApp.swift`, `Tests/AppIdentityTests.swift`, `doc/06-development-and-validation.md`.

---

<a id="dec-20260905-009"></a>
## DEC-20260905-009: Use complete original evidence or report an explicit input limit

- **Date:** 2026-09-05
- **Status:** Superseded for the initial context-window default and local error presentation by [DEC-20260907-001](#dec-20260907-001); full original evidence, configurable windows, and explicit preflight remain adopted.
- **Scope:** Insight context, vocabulary disclosure, factual source, long-meeting behavior
- **Replaces:** Historical refined-source preference in [DEC-20260904-007](#dec-20260904-007), matched-only vocabulary in [DEC-20260904-006](#dec-20260904-006), and the insight recent-window policy in [DEC-20260903-002](#dec-20260903-002). Title-specific recent input remains.

### Context and decision

Cumulative analysis cannot account for early agreements when source is silently restricted to the latest 6,000 characters. Exact vocabulary matching also hides correct spellings when recognition is wrong. Phase 2 requires declared, reviewable evidence coverage.

- Send complete original source through the frozen request cutoff and the complete confirmed meeting/personal vocabulary. Meeting spellings win case-insensitive duplicates. Focus can be cumulative or latest exchange; it does not silently change coverage.
- Historical insights and summaries use originals regardless of the refinement display toggle. Keep refinement additive and retain frozen source inside every snapshot. Manual input marks provisional text separately; automatic input is finalized-only.
- Expose the selected model's insight budget as an explicit saved AI setting (32,768 initially, 16,384–2,000,000 configurable). Preflight counts serialized UTF-8 bytes, instructions, Schema, framing allowance, and an 8,192-token output allowance. Treat it as a conservative estimate, not tokenization or discovered capacity; service errors remain authoritative.
- If input does not fit, reject before sending and show the estimated requirement. Do not truncate, silently compress, or label a recent excerpt complete. Documents are not added to insight requests; their core use is vocabulary extraction.
- Require one app-owned conclusion/points/evidence schema. Validate source IDs and verbatim quotes. Prompts require supported facts, later changes/retractions, unknown missing owners/dates, and English generated presentation.

### Rejected alternatives and rationale

- Recent-only input violates cumulative coverage. Reusing prior insights as facts can compound errors. Hierarchical compression/retrieval needs its own evidence and quality contract and is deferred.
- Match-only vocabulary cannot help with the recognition mismatch that motivated it. Full vocabulary increases disclosure and cost; the UI and privacy references explicitly describe that boundary.
- Refined source may contain model-introduced facts. Originals plus inspectable frozen evidence provide a consistent input contract, at the cost of retaining recognition errors.
- Per-provider tokenizers/window discovery are not reliably available across configured compatible services. Conservative explicit budgets keep failure honest, but can reject input that a model might actually fit and cannot guarantee server acceptance.

### Impact and validation

Removed the old insight cutoff, match filter, and refined-input path. Titles retain their own bounded helper. Tests cover early/late evidence beyond 6,000 characters, unmatched vocabulary, Unicode over-budget rejection, provisional capture, original-source summaries, strict evidence validation, and preserved snapshot versions. See [validation](phase-2-validation.md).

- **Files:** `Sources/Insights/InsightModels.swift`, `Sources/Insights/InsightEngine.swift`, `Sources/Insights/MeetingTitleGenerator.swift`, `Sources/AI/AISettings.swift`, `Sources/AI/AISettingsView.swift`, `Tests/InsightEngineTests.swift`.

---

<a id="dec-20260905-008"></a>
## DEC-20260905-008: Save each custom insight with its immutable request and result

- **Date:** 2026-09-05
- **Status:** Superseded for AI task lifetime and cross-meeting replacement by [DEC-20260906-009](#dec-20260906-009). Superseded by [DEC-20260905-017](#dec-20260905-017) for the manual concurrency limit; definitions, snapshots, automatic gates, standalone manual priority, and persistence behavior retained.
- **Scope:** Insight definitions, scheduling, cancellation, history, summary versions, persistence failure

### Context and decision

The fixed live result was overwritten in memory; historical regeneration replaced a single JSON field. Users need their own prompts, an immediate manual action, and a durable timeline they can review during and after recording.

- Each meeting owns editable definitions with stable IDs, title, prompt, scope, and automatic flag. The initial Meeting Overview is an editable preset with automatic updates off. There is one engine/schema/renderer for all items.
- Automatic work requires 45 seconds and 80 additional finalized characters per item. One automatic slot coalesces changes; one manual slot dispatches a clicked item immediately. Identical pending clicks coalesce; a newer manual request cancels earlier manual work and obsolete automatic work for its item.
- Append each successful result immediately with its exact request/configuration, cutoff/request and completion dates, active-recording offset, provider/model, source/vocabulary versions, and result. Removing a definition retains saved history.
- Choosing an older snapshot holds that selection; new arrivals only make Latest available. Reading saved history works without credentials/network. Export includes all saved versions.
- Pause/end/switch/deletion cancel requests; cancellation tokens and owner/definition lookup reject late responses. End itself requests no summary. Explicit combined Full Meeting Summary uses current definitions and appends a distinct version each time.
- Save failure preserves an unsaved value and local Retry Save, with no repeated provider call. Automatic updates pause for that item until it is saved. Unsaved values are explicitly not durable across quitting.

### Rejected alternatives and rationale

- Saving only at End risks losing every live result on interruption. Replacing one cache violates retention.
- A separate legacy fixed-insight engine or summary store creates inconsistent history and render contracts. Kind metadata separates summary from live results in one model.
- Speaker-only triggers overreact to acknowledgments. Interval/content gates provide deliberate frequency; these initial defaults are not claimed optimal from real-meeting measurements.
- Waiting for unrelated automatic items defeats manual intent. The second slot costs some concurrency; no automatic batch/queue framework is introduced.
- Storing only source IDs cannot reproduce provisional corrections. Exact inputs increase local storage and repeated request size, an accepted tradeoff for auditability in this release.

### Impact and validation

Removed `insightJSON`, the overwritten `current` result, and speaker/sentence trigger paths. Deterministic tests cover priority, coalescing, held late responses, prompt changes, exact input retention, append-only live/summary versions, offline rendering, older selection, deletion, and local save retry. See [validation](phase-2-validation.md).

- **Files:** `Sources/Insights/`, `Sources/History/InsightSnapshot.swift`, `Sources/App/InsightInspector.swift`, `Sources/Meeting/CaptureCoordinator.swift`, `Tests/InsightEngineTests.swift`, `Tests/MeetingWorkspaceTests.swift`.

---

<a id="dec-20260905-007"></a>
## DEC-20260905-007: Make the meeting the persistent owner of preparation

- **Date:** 2026-09-05
- **Status:** Superseded for vocabulary source metadata by [DEC-20260906-002](#dec-20260906-002); other decisions remain accepted.
- **Scope:** Meeting lifecycle, data ownership, local attachments, vocabulary, titles
- **Replaces:** New-meeting/unfinished-selection semantics in [DEC-20260905-004](#dec-20260905-004). UUID selection persistence remains.

### Context and decision

Preparation needs a saved meeting before recording. Creating records only at Start and deleting empty recordings would discard documents and settings when users never speak or capture cannot start.

- New Meeting persists a draft with creation time and selects preparation. Quick Start uses the same owner. Persisted `draft` is distinct from transient capture startup; interrupted recordings recover paused, while drafts remain drafts.
- Preserve preparation after startup failure and empty End. Deleting a meeting explicitly cascades through documents, vocabulary, definitions, snapshots, and transcript.
- Keep UTF-8 Markdown as managed text copies in SwiftData, bounded at 3 MB/file and 30 MB/meeting. Attachment is local; extraction is a separate explicit AI action. Identical copies deduplicate; changed content is a distinct attachment, removable explicitly. Confirmed terms keep original filename/excerpt after attachment removal.
- Reuse vocabulary extraction/review/retry with a meeting-owned save destination. Meeting spellings precede personal vocabulary; both English recognizers freeze one combined list at Start/Resume. Chinese recognition remains outside this customization path.
- Explicit user titles take precedence over generated titles. Creation and recording-start times remain distinguishable. Current UI edits save through explicit actions, and language edits persist on change.

### Rejected alternatives and rationale

A generic multi-meeting project hierarchy, external file bookmarks, document retrieval, and preparation migrations add scope without serving the core workflow. Managed text copies keep preparation independent of file moves and require no new library. A parallel global import destination is retained as a current personal-vocabulary feature, not a compatibility adapter. Meeting extraction never mutates that destination.

### Impact and validation

`MeetingWorkspace` extends SwiftData ownership; the coordinator no longer deletes empty records or uses a start-only creation path. The preparation View reuses the existing importer and candidate rows. Tests verify on-disk reopen, copy limits, empty/failed-start retention, source provenance, vocabulary isolation, title priority, cascade deletion, and selection. See [validation](phase-2-validation.md).

- **Files:** `Sources/History/MeetingWorkspace.swift`, `Sources/History/MeetingHistory.swift`, `Sources/Meeting/MeetingPreparationView.swift`, `Sources/Meeting/CaptureCoordinator.swift`, `Sources/Capture/VocabularyImportController.swift`, `Tests/MeetingWorkspaceTests.swift`, `Tests/MeetingSelectionTests.swift`.

---

<a id="dec-20260905-006"></a>
## DEC-20260905-006: Use English throughout the product and documentation

- **Date:** 2026-09-05
- **Status:** Superseded for interface localization and UI metadata formatting by [DEC-20260908-001](#dec-20260908-001), and generated insight language by [DEC-20260908-003](#dec-20260908-003). App identity, English prompt source/generated meeting titles/export templates, and documentation remain adopted.
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
- **Status:** Superseded
- **Superseded by:** [DEC-20260905-007](#dec-20260905-007) for draft creation/recovery, and [DEC-20260905-011](#dec-20260905-011) for missing/deleted-selection behavior.
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
- **Status:** Superseded
- **Superseded by:** [DEC-20260908-004](#dec-20260908-004) adopts an independent master switch; shared configuration ownership remains valid.
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
- **Status:** Superseded for vocabulary commit/dismissal semantics and picker order by [DEC-20260906-005](#dec-20260906-005), source metadata by [DEC-20260906-002](#dec-20260906-002), and request details/timing by [DEC-20260906-003](#dec-20260906-003); serial budgets, progressive results, and incomplete-only retry remain accepted.
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
- **Superseded by:** [013](#dec-20260904-013) replaces the combined 3 MB reading limit. [DEC-20260906-010](#dec-20260906-010) replaces the named-entity-only extraction rule. Request budget, serial work, retries, partial success, review, and explicit saving remain.
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
- **Status:** Superseded
- **Superseded by:** [DEC-20260905-009](#dec-20260905-009). Historical insights now use original source with retained exact evidence.
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
- **Status:** Superseded
- **Superseded by:** [DEC-20260905-009](#dec-20260905-009). Insights now send the complete applicable vocabulary.
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
- **Superseded by:** [003](#dec-20260904-003) changes regeneration; [DEC-20260905-006](#dec-20260905-006) changes title language/length. [DEC-20260906-009](#dec-20260906-009) replaces selection-driven cancellation. Independent requests, storage, and display remain.
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
- **Superseded by:** [DEC-20260904-004](#dec-20260904-004) replaces tolerant JSON parsing. [DEC-20260905-009](#dec-20260905-009) replaces the recent-only insight budget. Responsibility separation remains.
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
