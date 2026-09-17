# Live Captions and Translation Pipeline

> This describes the current implementation. See [Conversation rendering requirements](conversation-rendering-requirements.md) for the rendering contract, [DEC-20260917-002](DECISIONS.md#dec-20260917-002) for paragraph presentation, and [DEC-20260917-003](DECISIONS.md#dec-20260917-003) for boundary confirmation and translation requests.

## 1. The two inputs define speaker identity

The system distinguishes speakers at capture time rather than mixing audio and inferring identities:

| Input | Domain identity | Capture | Recognition |
|---|---|---|---|
| System output | `.remote` (other participant) | [`SystemAudioCaptureSCK`](../Sources/Capture/SystemAudioCaptureSCK.swift) | Independent [`NativeSpeechEngine`](../Sources/Capture/NativeSpeechEngine.swift) |
| Default microphone | `.mine` (you) | [`MicrophoneCapture`](../Sources/Capture/MicrophoneCapture.swift) | Independent [`NativeSpeechEngine`](../Sources/Capture/NativeSpeechEngine.swift) |

One-on-one meetings therefore need no diarization: identity comes from the physical channel. All people in system audio become `.remote`, so this is not a multi-party speaker identification solution.

## 2. Audio capture

### 2.1 System audio

[`SystemAudioCaptureSCK`](../Sources/Capture/SystemAudioCaptureSCK.swift):

- Uses the first available display to establish `SCStream`.
- Captures all system audio except the current app; no meeting-app selector.
- Requests 16 kHz mono Float32.
- Configures a minimal 2×2 video size because ScreenCaptureKit requires display capture even for audio-only use.
- Handles interleaved and planar PCM, downmixing to `[Float]`.

This replaced Core Audio Process Tap. The reason recorded in source is that enabling an AirPods microphone degraded the old tap's remote audio, while the SCK path was unaffected.

### 2.2 Microphone

[`MicrophoneCapture`](../Sources/Capture/MicrophoneCapture.swift) uses `AVAudioEngine.inputNode`:

- Requests permission before starting.
- Installs a tap in the device's native format and downmixes to mono before delivering callbacks.
- Observes `.AVAudioEngineConfigurationChange` and rebuilds the tap on input-device changes.
- Leaves resampling to the recognizer.

## 3. Recognizer lifecycle and concurrency

Each stream has an actor-isolated [`NativeSpeechEngine`](../Sources/Capture/NativeSpeechEngine.swift):

1. Request speech recognition authorization.
2. For English, create `DictationTranscriber(preset: .progressiveLongDictation)`; for Chinese, use `SpeechTranscriber(preset: .progressiveTranscription)`.
3. On first use of an English vocabulary version, build `SFCustomLanguageModelData` from saved names and acronyms, each with `PhraseCount(count: 1)`. Compile local model and vocabulary files and supply them through the `customizedLanguage` content hint. Empty vocabulary skips custom models. No custom pronunciations or model weights are configured.
4. Check and install system speech resources for the transcriber.
5. Query `SpeechAnalyzer.bestAvailableAudioFormat`.
6. Create `AnalysisContext`, also supplying vocabulary through `.general` contextual strings. Vocabulary adjusts candidate probabilities; it does not replace strings in recognized output.
7. Audio callbacks enqueue samples and the device sample rate at capture time as chunks in an `AsyncStream` retaining at most 64 chunks. Queued samples retain their original sample rate across device switches, and the real-time callback never accesses converter or Speech state.
8. Inside the actor, use `AVAudioConverter`'s streaming input-block API to resample to the recognizer format, then write `AsyncStream<AnalyzerInput>`.
9. Route nonfinal results to `onInterim` and final results to `onCommit`, awaiting the main actor's `CaptionStore` update.

[`CaptureCoordinator.makeSpeechEngine(for:sessionID:)`](../Sources/Meeting/CaptureCoordinator.swift) binds callbacks to `.remote`/`.mine` and the session UUID. Late results from an old recognizer fail the token check and cannot enter a new meeting.

### 3.1 English vocabulary and activation boundary

The app identity is `com.plus.samewave`, including its UserDefaults vocabulary domain. Models use `Application Support/SameWave/SpeechLanguageModel` and `com.plus.samewave.terms`. Vocabulary and caches under an older identity are not read or migrated; old files are not deleted.

[`SpeechVocabularySettings`](../Sources/Capture/SpeechVocabularySettings.swift) supplies 41 default terms on first launch, then persists the user's entire saved vocabulary in UserDefaults. Manual Add Terms accepts one phrase per line, preserves commas within phrases, removes blank lines, trims surrounding whitespace, and deduplicates case-insensitively. An invalid line blocks the whole add; terms are limited to 100 characters. An explicitly saved empty vocabulary stays empty rather than restoring defaults.

Settings > Vocabulary directly contains the Personal Vocabulary editor in the existing 600×540 Settings sheet. Switching to AI Services keeps the same presenter and dimensions. Configure AI Services selects that tab; Done closes Settings. The shared editor offers multiline Add Terms, inline row Save/Cancel, direct removal, and optional Markdown extraction. Each vocabulary action commits explicitly; AI Services has a separate retained draft and its Save/Cancel never changes vocabulary. The old bulk settings draft and import-to-draft merge path are removed.

The shared editor keeps its outer cards in one ordinary ScrollView. Saved terms and suggestions use separate LazyVStacks with stable row heights, so large vocabularies render nearby rows on demand without changing the scroll extent as rows appear. Inline saved-term validation stays within the row; its full explanation is available through the tooltip and accessibility label. Saved vocabulary and suggestions have independent view bodies, so tab navigation does not rebuild their data. Hidden vocabulary content rejects pointer/accessibility interaction and its focus/keyboard handlers check the active tab, avoiding a whole-list enabled-state change.

Personal Markdown selection loads local temporary inputs without making a request. Extract Vocabulary explicitly sends their text. Temporary files, uncommitted manual/row edits, selected suggestions, and disclosure/reading state belong to the app-session editor, so switching tabs or closing either vocabulary host retains them and lets extraction continue. Stop cancels current and pending requests while retaining results. Retry Incomplete uses the immutable original inputs and skips successful requests. Discard clears pending suggestions and progress only after extraction is stopped. App exit clears unfinished work and temporary files; saved terms persist.
Local input is UTF-8 `.md`/`.markdown`, at most 3 MB per file and 30 MB per selection, with no total body-character limit. Content is split into internal fragments of at most 18,000 characters, then grouped into serial AI requests of at most 20,000 characters. Fragments are assembly units, not individual API calls. Each request retries at most twice after its first failure; a third failed attempt is recorded and later requests continue.

Each successful request returns at most 50 terms under strict JSON Schema. The prompt prioritizes abbreviations, personal names, and specialized terminology valuable for English ASR. Ordinary words require both central importance and repeated mentions; capitals/headings alone do not qualify. It prefers compact spoken terms and shared roots while retaining meaningful multiword names. No client-side whitespace splitting is applied. Filenames are not sent. Candidates contain term strings only and are deduplicated against saved vocabulary, current suggestions, and previously received originals. Stable candidate IDs preserve edits and deselection during later arrivals. Add to Vocabulary validates selected rows only and deduplicates again at commit time. It never commits a manual draft. Save failures retain edits and selection for retry. Suggested Terms owns selection controls, Add, Discard, and success/error feedback, with repeated controls inside long cards. The global footer only dismisses. Progress and the latest failed reason appear inline; there are no request details, source metadata, document-content previews, or Review tab.

Meeting Preparation separates Context from Vocabulary. Context owns persisted managed Markdown copies; the meeting editor references the count and returns to Context for attachment changes. The same editor and extraction controller save to the meeting's vocabulary rather than personal settings. Each scope supports manual input without AI configuration. See [session data](03-session-lifecycle-and-data.md).
Starting or resuming a meeting freezes the combined confirmed meeting vocabulary and saved personal vocabulary in `CaptureCoordinator`, with meeting spellings taking precedence for case-insensitive duplicates and passes the same snapshot to both recognizers. Editing vocabulary during recording cannot change those recognizers; changes take effect at the next English start/resume. Chinese recognition does not use the English vocabulary.

Custom model directories are separated by locale and a SHA-256 vocabulary fingerprint. Prepared models are reusable for identical vocabulary; changed vocabulary creates a new configuration. Apple Speech training data and model files stay local. AI reuses saved vocabulary differently: refinement freezes the complete personal list at operation start, insights send the full applicable meeting/personal list with a saved version, and titles send none. These AI uses do not change local recognition's privacy boundary; see [AI insights and refinement](04-ai-insights-and-refinement.md).

### 3.2 Deterministic stopping

Pause/end stops capture first, then `NativeSpeechEngine.stop()`:

1. Closes sample input and converts all queued audio.
2. Ends analyzer input and calls `finalizeAndFinishThroughEndOfInput()`.
3. Waits for the Speech result stream, including every result's main-actor callback.

The last final ASR result is therefore in the store before sealing and final persistence. If Speech finalization fails, cancel result processing and preserve the best available text rather than waiting indefinitely.

## 4. Section model

[`Section`](../Sources/Meeting/MeetingModels.swift) is one independently translated unit shared by UI and persistence. A recognizer hypothesis and a speaker's conversational turn can each span several units. Several adjacent units form one visible paragraph:

| Field | Meaning |
|---|---|
| `id` | Monotonically increasing within a session; display order |
| `speaker` | `.mine` or `.remote` |
| `contentState` | `.open` / `.sealed`: whether newly added speech can extend this draft caption |
| `translationState` | `.pending` / `.translating` / `.done` / `.failed` |
| `committedSource` | Final ASR fragments assigned to this caption |
| `interimSource` | This caption's fragment of a cumulative volatile hypothesis |
| `targetText` | Current translation |
| `generation` / `requestedSource` | Latest requested source snapshot and its version |
| `translatedGeneration` | Latest displayed or invalidated result version; prevents stale translation publication |
| `startedAt` | Section opening time |

Content and translation states are orthogonal. Sealing prevents newly added speech from extending an old caption, but allows recognition corrections to its existing words and does not cancel translation.

## 5. Chronological captions during overlap

[`CaptionStore`](../Sources/Meeting/CaptionStore.swift) owns at most one open draft per speaker, separately from each unfinished recognition hypothesis. First words appear immediately. Continuous overlap grows both drafts until a caption boundary; it does not create one row per alternating word. A speaker returning after at least one second without added words opens after an intervening speaker, even before ASR finalization. Ordering follows observed recognition activity, not precise acoustic onset.

Source appears immediately and remains eligible for translation while boundary confirmation proceeds independently. `NLTokenizer` identifies candidate sentence endings. A comma, semicolon, or colon can also end a clause after at least 96 source characters (32 with Chinese), once following words exist. The prefix through a candidate must remain unchanged for 700 ms. Growth after the candidate, duplicate callbacks, and other-speaker updates do not extend its deadline. A changed prefix or removed punctuation replaces or cancels that candidate. Abbreviations, decimal numbers, and ellipses do not establish sentence endings.

When confirmed punctuation ends the current unit, sealing retains its ID, visible target, and translation generation. A late internal boundary can split the newest active unit: retain the prefix ID, append a new suffix ID, and transfer only the suffix's unfinished hypothesis ownership. Preserve committed and interim source exactly once. Invalidate translations covering the old combined unit before scheduling both new fragments; old successes and failures cannot restore an overlapping target. The source remains visible while new translations arrive. Already sealed units retain their ownership. Internal splits never move existing speech across another speaker's newer unit; that earlier active unit may contain several sentences until its next turn/size boundary or finalization.

Prefer the earliest eligible sentence or clause boundary before the size guard. Beyond 48 words or 240 source characters (96 with Chinese), the newest active unit confirms that boundary immediately; if none precedes the guard, split after the lexical word that reaches it. A batched hypothesis can produce several units in one callback. During overlap, new words reaching the guard start a later unit without relocating an earlier speaker's existing words. These are thresholds between lexical words, so one word can exceed the character count; corrections in sealed units can also exceed it. Count committed and interim source together.

A final commits recognized source once and confirms eligible boundaries immediately. Sentence-ended units seal; a short final without sentence-ending punctuation can continue in the same unit on the next hypothesis. Finality alone does not establish a sentence boundary. Sealing retains unfinished recognition ownership until the final result, and new speech after a confirmed boundary requests only its own translation. Genuine ASR corrections can still update and retranslate a sealed unit without reprocessing unchanged neighbors.

### 5.1 Cumulative source ownership

[`SpeechHypothesis`](../Sources/Meeting/SpeechHypothesis.swift) uses Apple's `NLTokenizer` word boundaries and Swift collection differences to match each revised hypothesis to its previous text. Display spelling, punctuation, and separators are preserved; matching ignores case and punctuation.

- Matched words retain their Section IDs. Replacements inherit the removed words' IDs; insertions before an existing matched word belong to that earlier fragment. These corrections do not acquire the floor. Confirming an internal boundary in the newest active unit explicitly transfers its suffix ownership, as described above.
- Unmatched trailing words extend the utterance and refresh its monotonic activity time. Continuous growth reuses the speaker's active Section; growth after a one-second gap opens a later Section when another speaker has intervened. Correction-only callbacks do not refresh activity. New Sections omit the cumulative prefix.
- A final commits each owned fragment once to its Section, corrects its spelling, clears interim text, and releases the recognition hypothesis. It can correct several sealed Sections without reordering them.
- A completely retracted fragment is removed, including its translation. IDs are never reused within the session, so late translation results cannot restore it.
- Final fragments such as "I'd now like", "to", and "quote from" continue within one unit until a sentence, clause/size, turn, or lifecycle boundary. Each source change remains eligible for immediate translation. Sentence/clause/length boundaries can also create further units within one callback.
- Pause/end drains ASR and then promotes any remaining fragments once, including those in sealed Sections. Empty or nonlexical callbacks never acquire the floor.

A native English `DictationTranscriber` probe with `audioTimeRange` enabled returned one coarse range for the entire interim hypothesis; detailed word timing arrived only at finalization. A separate SpeechDetector probe alongside DictationTranscriber returned no activity results, including for padded silence. The app uses text revision ownership, punctuation, bounded caption growth, and recognition inactivity. It does not claim acoustic VAD: delayed or batched ASR results can shift a boundary, and wholesale rewrites or changed tokenization can blur corrections versus new speech. Inactivity without punctuation or an intervening speaker does not split the latest draft. Capture channels retain their identities, including recognized echoes; multiple remote participants remain one Speaker.

### 5.2 Paragraph presentation

[`CaptionParagraphLayout`](../Sources/Meeting/CaptionParagraph.swift) groups adjacent units from the same speaker. A newly opened unit begins another paragraph after a sentence ending once the preceding paragraph contains at least 240 source characters (96 when it contains Chinese). Without a sentence ending, it can continue up to 360 characters (144 with Chinese) before the next unit starts a paragraph. A speaker change or at least 20 seconds between consecutive unit starts also begins a paragraph. Character boundaries are checked between units. A unit can cross the limit, and later corrections can exceed it.

`CaptionStore` retains assigned paragraph membership during the live session. Source corrections, translation arrivals, and draft promotion never move existing units into different paragraphs. Retractions remove their own spans and empty paragraphs while retaining other group identities. History rebuilds groups from original stored source using the same rule; the Original/Refined toggle only selects displayed text and cannot regroup paragraphs. Restoring a session rebuilds membership from the saved source, so corrections made before saving can affect that new layout. Paragraph membership is presentation state; stored Section IDs, original/refined text, counts, and the SwiftData schema do not change.

Live and history share paragraph grouping, joining rules, typography, and colors: one speaker/time header, continuous primary text, and continuous secondary original text for translated meetings. Live SwiftUI paragraphs style each unit independently; active spans use secondary color. English fragments retain word spacing, adjacent Chinese fragments join without added spaces, and joining invents no punctuation. Before any target is available the paragraph shows source once. As translations arrive, its source line supplies the complete original paragraph, including any units still awaiting translation. At a fixed width, live primary and total paragraph heights retain their measured maximum; a shorter target cannot pull the source line or following paragraphs upward. Resizing resets the reservation. History uses one selectable AppKit text document with complete natural-height layout when text or width changes, so Original/Refined can reflow normally and scrolling retains a stable extent. See [history rendering](03-session-lifecycle-and-data.md#5-history-and-export).

## 6. Translation scheduling

When source and target differ, a changed source snapshot triggers translation. Duplicate interims, identical finals, and sealing unchanged text do not create another generation or request. A failed snapshot may be retried. Same-language pairs create no translation requests.

### 6.1 Coalescing mailbox and consumer lifetime

[`TranslationBridge`](../Sources/Meeting/TranslationBridge.swift) keeps one pending snapshot per caption, replacing older waiting snapshots for that caption. Its first request is eligible after a 60 ms coalescing window. Subsequent dispatches for that caption are at least 400 ms apart, combining rapid ASR revisions while keeping source immediate. The pending deadline is the later of first enqueue plus 60 ms and the previous dispatch plus 400 ms; replacement never extends it. Different captions retain FIFO fairness under one active request, so queueing and model execution can add latency. No caption is evicted to make room for another. Useful in-flight results still publish while newer source waits. Pending/in-flight accounting includes these windows and supports pause/end's bounded idle wait. Consumer restart clears the dispatch history.

Each `run` owns its wake-up stream and consumer UUID. Cancelling an idle SwiftUI Translation task cannot close the mailbox for future consumers. Preparation failure, consumer cancellation, and request timeout settle all owned work and fail subsequent requests immediately until restart. An individual request error or empty response fails that request and lets the next Section proceed. No failure is represented as a successful empty translation.

A prepared translation request has a 15-second deadline. On timeout, the bridge marks work failed, calls the public macOS 26 `TranslationSession.cancel()`, and rejects late responses even if the framework does not promptly return. This deadline does not include first-use model preparation/downloads. Start/resume invalidates the SwiftUI configuration to prepare a fresh session. The existing five-second pause/end wait remains independent: source can be saved while a slow request is still completing.

### 6.2 Progress and generation checks

A response may update `targetText` when its generation is newer than the last displayed result and no newer than the latest request. It does not have to match the latest requested generation to provide interim progress. Thus sustained ASR updates cannot continually invalidate every useful translation. An older displayed version remains marked translating while current source waits; only completion of the latest snapshot marks it done, whether its Section is open or sealed. A new source snapshot moves done back to translating.

An internal split clears the combined target and raises the accepted generation floor through every request already issued for that unit. Both late successes and failures below that floor are ignored. Failures otherwise affect only the current requested generation. Session UUID checks in the coordinator and consumer UUID checks in the bridge reject old-meeting and old-consumer callbacks. Restored Sections are sealed; a missing saved translation is failed and displays source rather than pretending work is running.

### 6.3 Translation input

Each Apple Translation request contains exactly one unit's current `sourceText`. Its returned target is published directly. No preceding transcript, synthetic separator, output extraction, or second recovery request participates. Sentence and clause boundaries supply context inside the unit; cross-unit pronouns and terminology still depend on the translation model. Keeping a longer active sentence can improve completeness while increasing the amount of text a single revision changes. The dispatch interval limits request frequency, not the framework's wording changes or exact response cadence.

## 7. Overlap sequence

```mermaid
sequenceDiagram
    participant R as Remote ASR
    participant M as Microphone ASR
    participant S as CaptionStore
    participant T as TranslationBridge
    R->>S: interim (remote utterance)
    S->>T: section 0 snapshot
    M->>S: interim (reply)
    S->>T: section 1 snapshot
    Note over S: Both streams may grow continuously in their own Sections
    Note over R: At least one second without added remote words
    R->>S: cumulative interim with added speech
    S->>T: section 2 continuation source
    Note over S: Seal old remote turn; keep its prefix in section 0
    T-->>S: section 0 result (visible progress)
    R->>S: corrected final (cumulative utterance)
    S->>T: changed snapshots for sections 0 and 2
    Note over S: Commit each owned fragment once; keep turn order
```

## 8. Language pairs

- Independent source and target menus both use the fixed English labels English and Simplified Chinese, yielding four combinations.
- Source determines both ASR locales: `en-US` or `zh-CN`. English vocabulary applies only to an English source.
- Different languages use `TranslationSession` to produce `targetText`, displayed in the full workspace as independent spans within paragraphs above secondary source text. Until a unit has a translation, its source is its primary span. Active drafts use secondary text color. Sealing promotes the same span without clearing its visible translation. Live paragraphs reserve primary/source layout space as described above. Pending/updating work has no spinner or Translating text; explicit failures retain their source/failure label.
- Simple Mode renders the complete conversation through the same `CaptionsView` as the full window. Paragraph membership, bilingual source/target presentation, Speaker/You labels, translation failure handling, height reservation, and automatic scrolling are shared. Reading earlier text suspends following until the reader returns to the bottom. The panel changes window controls and background opacity only. Changing the window presentation retains the same `TranslationPump` attachment and `CaptureCoordinator`; no second consumer, capture pipeline, or transcript store is created.
- Matching languages create neither a Translation session nor requests. The coordinator sets `targetText = sourceText`; the UI hides duplicate source echo.
- Both menus are disabled after starting to keep recognizers, translation, and the persisted pair consistent throughout the meeting.

## 9. Key invariants

1. At most one open draft per speaker; sentence and clause captions retain independent IDs, translations, and history.
2. IDs increase monotonically; first-observed Section order never changes.
3. Existing words retain ownership across corrections/finals except an explicit boundary split within the newest active unit; a return after recognition inactivity opens after an intervening speaker without waiting for finalization.
4. Translation completion is independent of sealing and advances by displayed generation.
5. Pending requests coalesce within one Section, never evict another Section.
6. Restored Sections are sealed, with done or missing-translation failure state.
7. Same-language meetings send no translation requests and show no duplicate text.
8. Old-session and old-consumer callbacks cannot modify new work.
9. Pause/end drains ASR before sealing, preserves both interim tails, and bounds the translation wait.
10. Same-height text revisions never request scrolling. Content growth follows the bottom only while the reader remains there; scrolling into history retains the reading position until the reader returns to the bottom.
11. Translation units and visible paragraphs have separate boundaries. Existing live paragraph membership survives text revisions, and history groups original source independently of the refinement display toggle.
