# Session Lifecycle and Data

> Main implementation: [CaptureCoordinator](../Sources/Meeting/CaptureCoordinator.swift), [MeetingHistory](../Sources/History/MeetingHistory.swift), [MeetingWorkspace](../Sources/History/MeetingWorkspace.swift), [InsightSnapshot](../Sources/History/InsightSnapshot.swift), [TranscriptExporter](../Sources/History/TranscriptExporter.swift).

## 1. Persistent meetings and transient capture

A meeting owns preparation before capture begins. Its persisted status is `draft`, `recording`, `paused`, or `ended`. The coordinator independently uses `idle`, `starting`, `recording`, `pausing`, `paused`, and `stopping` for resource transitions. An idle coordinator may have a draft mounted; attaching documents does not start recording.

New Meeting saves a draft immediately, selects it, and displays preparation. Quick Start creates the same draft before starting capture, without requiring documents, custom prompts, or AI. Drafts include an editable Meeting Overview insight with automatic updates initially off.

`createdAt` records workspace creation. `startedAt` is set when capture is requested; for drafts it is not a recording timestamp. `endedAt = startedAt + elapsedSeconds` remains the duration endpoint, excluding pauses. Insight cutoffs and completions are independent wall-clock dates; their recorded-time offsets exclude pauses.

## 2. Lifecycle and selection

### Start and failure

Start saves the selected draft's language pair and recording start/status before opening system audio and both recognizers. The local caption store and timing initialize for this recording. Required system-audio startup failure tears down resources and returns the same meeting to draft status, retaining documents, terms, title, and definitions. It no longer deletes empty meetings. An initial microphone failure remains visible while allowing system audio to continue.

### Pause and resume

Pause cancels pending insights, accumulates active recording time, stops capture and autosave, drains ASR callbacks, seals the floor, and waits at most five seconds for translation. It then saves the transcript and paused status. A failed save retains the mounted transcript for retry and prevents switching.

Resume freezes the current combined meeting/personal vocabulary for both English recognizers, preserves prior Sections and elapsed time, and rebuilds capture. Failure returns to paused. Automatic insight scheduling starts a fresh interval/content baseline at successful start/resume; it does not generate merely because old transcript text exists.

### End

End cancels outstanding insight requests and follows the same capture/ASR/translation drain. Final text and ended status save together. Empty meetings remain saved. Successful completion selects the same meeting's history; live insight snapshots remain available. End does not request or relabel a full summary. A failed final save leaves the meeting paused with its source in memory and an explicit retry message.

### Switching and recovery

- Selecting another draft, paused meeting, or ended meeting suspends and saves the mounted recording first. Ended-history navigation uses the same coordinator boundary.
- Only one recording is mounted. Drafts mount without capture; paused records restore sealed Sections and resume IDs above the maximum saved Section ID.
- Persist the displayed meeting UUID in UserDefaults `selectedMeetingID` whenever selection changes. History selection takes precedence over a mounted record.
- On launch, interrupted `recording` records become paused. Drafts remain drafts. Restore the saved UUID; missing/invalid/deleted selections choose the most recently created stored meeting. Selection never starts capture.
- Deleting the displayed meeting selects another mounted meeting if present, otherwise the most recently created remaining meeting. Deleting another meeting preserves selection. The selected UUID persists immediately. When no meetings remain, clear the transcript and show a real empty state without a capture dock or synthetic sidebar row; New Meeting explicitly creates a draft.
- A normal quit synchronously saves visible source already received; a crash retains the latest four-second autosave. Neither can recover audio still inside recognition because audio is never stored.

## 3. Ownership and preparation

`MeetingRecord` owns cascade relationships to:

| Model | Saved content |
|---|---|
| `TranscriptLine` | Section ID/order, speaker, spoken date, original source/translation, additive refined variants |
| `MeetingDocument` | UUID, original filename, managed UTF-8 Markdown text copy, import date |
| `MeetingVocabularyTerm` | Confirmed spelling |
| `InsightDefinition` | Stable UUID, title, prompt, scope, automatic-update choice, creation time |
| `InsightSnapshot` | Immutable result payload, exact input/configuration, owner, kind, request/completion dates |

The meeting also stores user title, AI title, language pair, creation/recording dates, cached line count, refinement date, and glossary. A nonblank user title always wins. Save or Return commits the title in Preparation; unsaved typing is a local field draft. The saved title survives capture and reopening. Automatic title generation during refinement is skipped when the saved user title is nonblank, and a late response cannot be applied after a user title has been saved.

Markdown attachments are local text copies, up to 3 MB per file and 30 MB per meeting. The original file can move or disappear. `VocabularyDocumentLoader.merging` validates and deduplicates additions for both meeting attachments and personal temporary files, preserving order and counting each distinct filename/content pair once. Changed content becomes a distinct attachment. Remove the previous attachment explicitly when replacing it. Removal preserves confirmed terms; deleting the meeting cascades through all artifacts. No document text is sent merely by attachment. Extract Vocabulary is a separate explicit AI action.

Preparation separates Context attachment management from Vocabulary editing. Title, term, and insight actions save explicitly; language choices persist on change. The coordinator retains one VocabularyEditorStore per meeting, including manual drafts, row edits, source-independent extraction, candidates, selection, and reading state. Closing preparation or switching meetings preserves that session. The meeting sheet and Settings Vocabulary tab reuse VocabularyEditorView. Personal editing stays within the fixed-size Settings sheet; switching tabs or closing Settings preserves its app-owned editor state. Suggested Terms owns its selection, Add to Vocabulary, Discard, and feedback; selected saves leave unchecked candidates and unrelated manual edits intact. Saved-row edits and removal use the same explicit destination transaction. A failed vocabulary write restores its affected rows without rolling back unrelated model edits. Done dismisses without saving or cancelling. Stop retains partial results, while Discard clears suggestions/progress when stopped. Retry uses the original extraction input. Successful meeting deletion invalidates its editor and rejects late results. Confirmed preparation persists across relaunch; pending edits and suggestions last only until app exit. Vocabulary previews up to twelve saved terms in wrapping chips and shows the remaining count. Its extraction card lists every Context filename and byte size in the same stable import order, read-only. Context shows filename, size, and direct removal without content previews; returning from Vocabulary focuses that existing card rather than opening another sheet.

## 4. Incremental transcript and snapshot writes

`sync` upserts meaningful Sections by stable `sectionId`, updates ordering/text/dates, deletes pruned empty Sections, and refreshes cached count/status/duration in one save. Refinement writes separate fields and never overwrites originals.

Every successful insight appends a new snapshot immediately. The payload retains the full source used, including separately marked provisional text, prompt/configuration, complete applicable vocabulary, provider/model label, budget, and timestamps. Later refinement or prompt changes cannot rewrite that evidence. Reading saved snapshots requires neither credentials nor networking. See [AI insights](04-ai-insights-and-refinement.md) for dispatch and coverage policy.

SwiftData errors propagate. Failed saves roll back model mutations. The engine retains an unsaved generated value in memory, labels it unsaved, and offers Retry Save without another provider request. Retry is idempotent by snapshot UUID. Unsaved results are not durable across quitting; the UI explicitly says to retry before quitting. Automatic generation for an item with an unsaved result pauses until it is saved. Deleting its meeting discards pending/unsaved results only after the deletion succeeds.

A database-open failure blocks meeting work rather than starting a nonpersistent replacement. There are no custom schema migrations, obsolete `insightJSON` readers, or dual writes.

## 5. History and export

The sidebar lists drafts, recording, paused, and ended meetings by creation date. Both user and AI titles retain the meeting date in secondary metadata; an untitled meeting uses the date as its primary label. History contains original/refined transcript display and the same insight timeline. Definitions can be edited or removed without deleting previously saved results; removed definitions remain browsable through their snapshots.

Markdown export includes every saved insight version in request order, distinguishing manual, automatic, and full-summary kinds, with cutoff, coverage, provisional disclosure, conclusions, points, and summary parts. Insights no longer request or export supporting evidence quotes. The transcript portion prefers refined text when available and preserves source echoes only for translated meetings. Export never changes stored originals. Undecodable saved snapshots are retained and reported rather than silently omitted.

## 6. Validation boundaries

Deterministic tests cover draft restart, empty finish, failed-start state retention, title ownership, attachment copies and limits, vocabulary isolation, definition/snapshot ownership, cascade deletion, pause/end selection, and snapshot save retry. On-disk reopen tests verify serialization beyond a single in-memory context. Actual audio, permissions, recognition accuracy, and live translation require signed-app smoke tests; see [Phase 2 validation](phase-2-validation.md).
