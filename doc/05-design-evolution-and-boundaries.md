# Design, Evolution, and Boundaries

## 1. Principles reflected in source

### 1.1 Use system boundaries to reduce algorithmic work

The key choice is separating you and the other participant into two inputs. In one-on-one meetings, physical sources already provide reliable identity, avoiding diarization model size, latency, and label drift.

This trades product breadth for simpler, more deterministic implementation.

### 1.2 Real-time systems prioritize the latest snapshot

Two paths share this pattern:

- Translation replaces pending requests within a Section with its latest generation.
- Insights coalesce all changes during a request into one dirty flag.

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

A record is created at start, not after End. Stable Section IDs support incremental SwiftData upsert, letting pause, crash recovery, and multiple unfinished meetings share one model.

### 1.6 Let platform frameworks handle common complexity

The main target has no third-party dependencies. Apple frameworks supply capture, recognition, translation, data, and UI. This simplifies footprint and supply chain, while binding the app to macOS 26, platform API lifecycles, language resources, and permissions.

### 1.7 Lifecycle transitions await actual completion

Pause/end no longer guess completion through delays. Capture, bounded audio streams, Speech finalization, main-actor callbacks, translation in-flight work, and SwiftData save have explicit boundaries. Only Translation uses a five-second ceiling because its system service is outside app control; timeout saves source and rejects late writes.

## 2. Architectural evolution

The product has grown from a caption utility into a meeting workspace with transcription, translation, history, and optional AI:

| Earlier design | Current design | Motivation/result |
|---|---|---|
| Per-app Core Audio Process Tap | ScreenCaptureKit for all system audio | Avoid remote audio degradation after enabling the microphone; remove app selector |
| WhisperKit / multiple engines | Two Apple SpeechAnalyzers | Unified ASR; remove third-party model dependency |
| Menu bar + floating NSPanel | Dock + menu bar + three-column window | One workspace for history, captions, insights |
| Live captions/export only | Incremental SwiftData history and recovery | Persistent meeting records |
| Simple translation queue | Per-Section mailbox + generation | Avoid interim backlog and stale writes |
| Local caption utility | Optional strict JSON Schema insights/refinement | In-meeting assistance and post-meeting cleanup |
| Boolean lifecycle + 900 ms save delay | Explicit state + awaitable finalization | Avoid illegal transitions, lost final words, stale-session writes |
| Unsafe Sendable + minimal checking | Actor/MainActor isolation + complete checking | Compiler-checked capture/recognition boundaries |
| No test target | XCTest domain regressions | Protect Sections, scheduling, persistence, AI logic |
| One all-purpose insight object | `InsightEngine` + `TranscriptRefiner` + `MeetingTitleGenerator` | Separate live single-flight, post-meeting batches, and one-shot titles |

Old implementations are no longer selectable paths. [`Sources/`](../Sources/) and [`project.yml`](../project.yml) define the current architecture.

## 3. Requirements versus implementation

[Conversation rendering requirements](conversation-rendering-requirements.md) describes explicit `IDLE/SINGLE/OVERLAP`, speech-start/end events, and correction-only changes after sealing. The current ASR API supplies interim/final text rather than reliable two-stream VAD events, so implementation uses a single floor acquired by final commits.

This is simple, resists partial-result jitter, and suits a single-column UI, but:

- Turns switch after the acoustic interruption begins.
- Actual overlap is serialized by final-result arrival order.
- Sealed-ASR correction is not explicitly implemented.
- Long pauses do not independently end turns; a continuing speaker may remain in the same Section.

Strict compliance with the baseline requires more than another enum in `CaptionStore`: capture/recognition must first provide trustworthy per-stream speech start/end events, with defined text ownership and correction semantics during overlap.

## 4. Current boundaries and technical debt

### 4.1 Product

- One-on-one scope; all remote participants appear as Speaker.
- Global system capture can include audio from other apps.
- English and Simplified Chinese only, in both translation directions or direct same-language display.
- No saved audio, so no ASR reruns or retrospective speaker correction.
- macOS 26+, without older-system compatibility.
- App-owned text and documentation use English; selected transcript languages remain independent.

### 4.2 Engineering

- Unit tests cover `CaptionStore`, `TranslationBridge`, SwiftData upsert/empty-record deletion, AI context, and parsing. Real Speech, Translation, permissions, and full UI flows still lack automated integration coverage.
- Both Swift 6 targets use `SWIFT_STRICT_CONCURRENCY=complete`. `NativeSpeechEngine` is an actor; capture and coordination use MainActor. No `@unchecked Sendable` or `nonisolated(unsafe)`.
- The main window is split into container, sidebar, stage, and Inspector. `CaptureCoordinator` remains the vertical session orchestrator. Split further only for new independent I/O/state responsibilities, not to reduce line count with more indirection.
- `build.sh` hardcodes a personal Apple Development certificate and is not directly portable to other developers.
- Translation drain waits at most five seconds, prioritizing ending and source persistence over complete slow translations.
- Live AI uses a provider-independent 6,000-character budget, not exact token counting; long meetings prioritize recent topics.
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
5. Does it affect crash recovery? Validate the full lifecycle from start-time persistence, not only a successful stop.
6. Does it send more data off-device? Reflect that explicitly in settings and product copy.
