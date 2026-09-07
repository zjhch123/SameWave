# Design, Evolution, and Boundaries

## 1. Principles reflected in source

### 1.1 Use system boundaries to reduce algorithmic work

The key choice is separating you and the other participant into two inputs. In one-on-one meetings, physical sources already provide reliable identity, avoiding diarization model size, latency, and label drift.

This trades product breadth for simpler, more deterministic implementation.

### 1.2 Real-time systems prioritize the latest snapshot

Two paths share this pattern:

- Translation replaces pending requests within a Section with its latest generation, while publishing completed generations that advance visible progress. Pending source does not invalidate every in-flight result.
- Insights keep one automatic request and evaluate the latest complete input after interval/content gates. Manual generation takes priority; explicit batches fill available slots under a shared cap of six active insight requests.

Interim ASR is volatile. Replaying every hypothesis in order adds latency without value; resources should catch up with the user's current view.

### 1.3 Separate orthogonal states

Section content and translation lifecycles are separate. `sealed` is not `done`, so speaker changes, pause, and stop do not prevent already-started translations. This implements the requirement that segmentation and translation be orthogonal.

### 1.4 Preserve original facts

AI refinement writes only `refinedSource/refinedTarget`, leaving ASR and live translations intact. This supports:

- Checking whether AI changed meaning.
- Per-line use of originals when batches fail.
- Original/Refined switching.
- Future regeneration with a better model.

### 1.5 Save from the start

A record is created before recording, so preparation has the same persistent owner as later transcripts and insights. Stable Section IDs support incremental SwiftData upsert, letting pause, crash recovery, and multiple unfinished meetings share one model.

### 1.6 Let platform frameworks handle common complexity

The main target has no third-party dependencies. Apple frameworks supply capture, recognition, translation, data, and UI. This simplifies footprint and supply chain, while binding the app to macOS 26, platform API lifecycles, language resources, and permissions.

### 1.7 Lifecycle transitions await actual completion

Pause/end no longer guess completion through delays. Capture, bounded audio streams, Speech finalization, main-actor callbacks, translation in-flight work, and SwiftData save have explicit boundaries. Translation draining uses a five-second ceiling because its system service is outside app control; timeout preserves source. Prepared requests separately expire after 15 seconds, fail current/queued work, and cancel the session. Session identity rejects writes after unmounting.

## 2. Architectural evolution

The product has grown from a caption utility into a meeting workspace with transcription, translation, history, and optional AI:

| Earlier design | Current design | Motivation/result |
|---|---|---|
| Per-app Core Audio Process Tap | ScreenCaptureKit for all system audio | Avoid remote audio degradation after enabling the microphone; remove app selector |
| WhisperKit / multiple engines | Two Apple SpeechAnalyzers | Unified ASR; remove third-party model dependency |
| Menu bar + floating NSPanel | Dock + menu bar + three-column window | One workspace for history, captions, insights |
| Live captions/export only | Incremental SwiftData history and recovery | Persistent meeting records |
| Single overwritten insight | Meeting-owned immutable input/result snapshots | Persistent live history and full summaries |
| Simple translation queue | Per-Section mailbox + progressive result generations | Avoid interim backlog, translation starvation, and stale writes |
| Final-bound utterance Sections | Recognition activity plus cumulative word ownership | Separate resumed turns before ASR finalization while keeping continuous overlap readable |
| Local caption utility | Optional strict JSON Schema insights/refinement | In-meeting assistance and post-meeting cleanup |
| Boolean lifecycle + 900 ms save delay | Explicit state + awaitable finalization | Avoid illegal transitions, lost final words, stale-session writes |
| Unsafe Sendable + minimal checking | Actor/MainActor isolation + complete checking | Compiler-checked capture/recognition boundaries |
| No test target | XCTest domain regressions | Protect Sections, scheduling, persistence, AI logic |
| One all-purpose insight object | `InsightEngine` + `TranscriptRefiner` + `MeetingTitleGenerator` | Separate bounded insight concurrency, serial refinement batches, and one-shot titles |

Old implementations are no longer selectable paths. [`Sources/`](../Sources/) and [`project.yml`](../project.yml) define the current architecture.

## 3. Requirements versus implementation

[Conversation rendering requirements](conversation-rendering-requirements.md) separates chronological display turns from unfinished recognition hypotheses. Continuous overlapping growth stays in each speaker's active paragraph. A return after one second without added recognition opens a turn after an intervening speaker; matched/revised words retain earlier ownership. A final may correct several sealed fragments without moving the continuation above an intervening speaker.

Native English interim timestamps covered the whole cumulative hypothesis, so they could not provide immediate word boundaries. Word alignment with Apple's tokenizer and Swift collection differences supplies text ownership; a monotonic one-second recognition-inactivity rule distinguishes returns from continuous overlap. A SpeechDetector/DictationTranscriber probe did not report activity, including with padded silence. ASR batching or wholesale rewrites can still shift boundaries; this is observed recognition activity, not acoustic VAD or exact diarization. Long silence alone does not end a turn, and all remote people still share one capture identity. See [DEC-20260907-004](DECISIONS.md#dec-20260907-004).

## 4. Current boundaries and technical debt

### 4.1 Product

- One-on-one scope; all remote participants appear as Speaker.
- Global system capture can include audio from other apps.
- English and Simplified Chinese only, in both translation directions or direct same-language display.
- No saved audio, so no ASR reruns or retrospective speaker correction.
- macOS 26+, without older-system compatibility.
- App-owned text and documentation use English; selected transcript languages remain independent.

### 4.2 Engineering

- Unit tests cover `CaptionStore`, `TranslationBridge`, SwiftData upsert/draft retention and artifact ownership, AI context, and parsing. Real Speech, Translation, permissions, and full UI flows still lack automated integration coverage.
- Both Swift 6 targets use `SWIFT_STRICT_CONCURRENCY=complete`. `NativeSpeechEngine` is an actor; capture and coordination use MainActor. No `@unchecked Sendable` or `nonisolated(unsafe)`.
- The main window is split into container, sidebar, stage, and Inspector. `CaptureCoordinator` remains the vertical session orchestrator. Split further only for new independent I/O/state responsibilities, not to reduce line count with more indirection.
- `build.sh` hardcodes a personal Apple Development certificate and is not directly portable to other developers.
- Translation drain waits at most five seconds, prioritizing ending and source persistence over complete slow translations.
- Insights use a configured full-input budget with conservative byte-based preflight. Oversized meetings fail explicitly; no recent-only excerpt is mislabeled complete. Title generation alone retains its recent 6,000-character limit.
- App termination can synchronously save the store snapshot but cannot drain audio still in Speech.

### 4.3 Repository and documentation

- Product source lives only in [`Sources/`](../Sources/). External directories are not build inputs or runtime dependencies.
- [`project.yml`](../project.yml) is authoritative; generated `SameWave.xcodeproj` is not maintained manually.
- Root [`README.md`](../README.md) serves users, `01`–`06` describe current implementation, requirements preserve the design baseline, and [`DECISIONS.md`](DECISIONS.md) explains important choices.

## 5. Evaluating future changes

Follow the existing approach of a small complete workflow before another layer:

1. Is the scenario still one-on-one with two physical channels? If not, reconsider identity first.
2. Does it change Section invariants? Write transition examples/tests before UI changes.
3. Does it require every intermediate event or only the latest snapshot? Prefer coalescing in real-time paths.
4. Does it modify factual data? Keep AI-derived results additive.
5. Does it affect crash recovery? Validate the full lifecycle from draft creation and start-time persistence, not only a successful stop.
6. Does it send more data off-device? Reflect that explicitly in settings and product copy.
