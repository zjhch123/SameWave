# Phase 2: Meeting Workspaces and Persistent AI Insights

- **Status:** Core requirements P2-R01–P2-R09 implemented on `phase2`.
- **Updated:** 2026-09-06, for V2 release review.
- **Purpose:** Define the accepted V2 scope and observable behavior. Earlier proposals are superseded by this specification; decision history remains in [DECISIONS.md](DECISIONS.md).
- **Validation:** [Phase 2 validation](phase-2-validation.md) maps the requirements to tests and identifies remaining real-service checks.

## 1. Release scope

Each meeting is a persistent workspace for optional preparation, live captions, custom AI insights, and later review. V2 keeps the native Apple-style three-column shell and the existing local audio, recognition, and translation pipeline. It adds meeting ownership and insight history without introducing a generic project hierarchy, another provider engine, or third-party dependencies.

| ID | Accepted requirement |
|---|---|
| P2-R01 | Create and save a meeting before capture; retain its preparation, configuration, transcript, and results. |
| P2-R02 | Attach Markdown and extract reviewable meeting vocabulary, isolated from personal vocabulary and other meetings. |
| P2-R03 | Define meeting-specific insights with a title, prompt, focus, and optional automatic updates. |
| P2-R04 | Generate a chosen insight from the visible conversation as soon as shared capacity is available; also support generating all editable insights. |
| P2-R05 | Gate automatic generation by elapsed time and new finalized content, rather than speaker changes. |
| P2-R06 | Append timestamped results and let users hold an older version while new results arrive. |
| P2-R07 | Persist live insight history with the meeting for offline reading after End and relaunch. |
| P2-R08 | Explicitly generate and regenerate a complete post-meeting summary while retaining live history. |
| P2-R09 | Analyze the complete original transcript through a frozen cutoff, or fail visibly when the full input exceeds the configured budget. |

Recognition improvements and AI factual quality require representative real-service evaluation; extracting a vocabulary or passing deterministic tests does not establish those quality claims.

## 2. Meeting lifecycle and preparation

New Meeting immediately saves and selects a `draft`. Preparation is optional, and AI configuration is not required to start local captions. Persisted meeting status is `draft`, `recording`, `paused`, or `ended`; transient capture startup/teardown remains coordinator state. Creation time and recording start time are distinct.

Preparation has four cards:

- **Meeting title:** Save or Return commits the field. A nonblank saved user title takes precedence and prevents an AI title request during transcript refinement. A title saved during generation rejects the late result. Unsaved typing remains a local field draft. Clearing the user title reuses an existing AI title; if neither exists, the next refinement may generate one.
- **Context:** Attach UTF-8 `.md` or `.markdown` files as local managed text copies. Show every filename, byte size, and direct removal action, without a body preview.
- **Vocabulary:** Preview up to twelve saved terms in wrapping chips with a remaining count. Manage Vocabulary opens the shared editor for this meeting.
- **AI Insights:** Add/Edit opens the native definition sheet. Removed definitions retain their saved versions in the result archive.

Saved preparation survives meeting switching, relaunch, failed capture startup, and End without speech. Pause/resume preserves transcript and accumulated recording time. Deleting a meeting cascades through its documents, terms, definitions, snapshots, and transcript. Deleting the displayed meeting selects a remaining stored meeting; deleting the last one shows an empty state. Selection never starts recording automatically.

See [session lifecycle and data](03-session-lifecycle-and-data.md) for transition, autosave, restoration, and save-failure behavior.

## 3. Documents and the shared vocabulary editor

### Ownership and limits

Context owns meeting documents. Identical filename/content copies deduplicate; changed content is a separate attachment. Each file is limited to 3 MB, and each selection or retained destination to 30 MB. Validate distinct additions before changing the destination. Removal keeps confirmed vocabulary and the running extraction's frozen input.

Meeting Vocabulary and Settings > Vocabulary share one editor, normalization rule, extraction controller, and row components. Their saved destinations stay separate:

| Surface | Document input | Persistence |
|---|---|---|
| Meeting Vocabulary | Complete read-only Context filename/size list in import order; Manage Context returns to the attachment controls | Confirmed terms belong to that meeting |
| Settings > Vocabulary | Choose temporary local Markdown files, with removable file rows | Confirmed personal terms apply across meetings |

Choosing or attaching files stays local. Extract Vocabulary is the explicit action that sends document text to the saved AI service. Document bodies and filenames do not enter insight or refinement requests through attachment. Vocabulary extraction sends text without filenames.

### Editing, extraction, and dismissal

Manual multiline Add, saved-row Save/Cancel, Remove, and Add to Vocabulary each commit explicitly to the displayed scope. They are independent of AI Services Save/Cancel. Invalid manual input blocks the whole add; invalid selected suggestions block their save, while unchecked invalid suggestions do not. Case-insensitive duplicates retain the first spelling, with meeting spelling taking precedence when composing recognition/insight vocabulary.

Extraction splits text into fragments of up to 18,000 characters and requests of up to 20,000 characters. Requests are serial, retry twice after the first failure, and continue after exhausted failures. Each success returns up to fifty single-line terms of at most one hundred characters. Generated terms require user confirmation; no per-term source metadata or request-details view is collected or presented.

Suggested Terms owns selection, Add, Discard, and success/error feedback. Long suggestion cards repeat their actions within the card. Results appear incrementally without resetting edits, selection, or reading position. Stop retains partial results. Retry Incomplete uses the original provider and input and skips succeeded requests. Discard clears unfinished suggestions only when stopped.

Settings embeds vocabulary directly beside AI Services in the same fixed-size sheet. There is no separate vocabulary window, nested vocabulary sheet, Manage landing page, or Review tab. Done dismisses without cancelling vocabulary extraction. App-owned editor state retains temporary files, drafts, suggestions, and reading position across tab changes and dismissal; these unsaved values last until app exit. Confirmed terms persist. Deleting the owning meeting invalidates its editor and rejects late extraction replies.

Both English recognizers freeze meeting-plus-personal vocabulary at Start/Resume. Changes during recording wait for Resume. Chinese recognition does not use English customization. See [live captions and translation](02-live-captions-and-translation.md).

## 4. Insight definitions, requests, and history

Every draft copies the current default insights from Settings > Insights into independent meeting definitions. The unset preference begins with one editable Meeting Overview and automatic updates off; users can add, edit, or remove defaults, including keeping an empty list. Default edits affect only subsequently created meetings. Definitions appear newest first in the inspector. Definitions support cumulative or latest-exchange focus; both receive the same full original transcript, with focus expressed in the instruction.

Each custom card has a refresh icon. Custom Insights has Generate for all editable definitions, including Overview. A batch freezes its source, provisional text, vocabulary, definitions, provider/model, and cutoff when clicked. It fills up to six active insight requests and queues the rest. Every success appends its own immutable snapshot, even when replies complete out of order. Stop cancels the batch; an individual Stop removes only that item.

Automatic generation requires at least 45 seconds since the item's previous dispatch/start/resume and 80 new finalized source characters. Only one automatic request runs at a time, counted within the six-request limit. Eligible items rotate by oldest dispatch. Speaker changes and time without new content do not dispatch requests. Later source coalesces into the next eligible evaluation.

Standalone manual generation starts when a shared slot is available, supersedes older manual work in its own meeting, and cancels obsolete automatic work for the same item. Other meetings keep their active and queued requests; all batches and standalone requests share the six-request cap. Identical active requests coalesce. Manual input retains visible provisional recognition in a separate field; automatic input uses finalized source only. Prompt/vocabulary edits affect the next request, never an in-flight or saved input.

Snapshots retain exact input/configuration, result, manual/automatic/summary kind, cutoff and completion timestamps, recorded-time offset, provider/model label, and budget. Each card independently follows latest by default or holds a selected historical version. Key-point expansion persists per meeting/definition across versions and relaunches. Reading requires no AI configuration. A save failure retains the generated value with Retry Save; retry does not call the provider or duplicate an already-saved snapshot. Unsaved values are not durable across quitting.

Meeting switches retain manual insights, summaries, queues, and errors for the app session. Pause and End stop automatic work while manual requests retain their frozen input. Explicit Stop and successful deletion cancel the affected work only. Tokens and ownership checks reject late responses. Existing successful versions remain saved. A removed definition keeps saved history and any generated value awaiting a save retry.

## 5. Result presentation and post-meeting summary

One response contract serves every insight: `conclusion`, `points`, and nullable `summary`. The conclusion is the direct answer of at most 300 characters. Broad overviews and full summaries use five arrays: topics, suggestions, action items, decisions, and open questions. Focused prompts have no point-count target or maximum; each point retains a 240-character text bound and summary is null. Selection requires relevance to the actual question, source support, and material effect on understanding, decisions, actions, risks, or dependencies. Later corrections replace obsolete positions; repeated claims merge and independent commitments remain separate. Facts, inferences, and recommendations must remain distinguishable. Irrelevant missing details, generic advice, and repeated conclusion content are excluded. No relevant discussion, or a complete answer already in the conclusion, yields empty points. Full-summary validation requires the structured parts. Each summary part retains its existing bound of eight nonblank items, each at most five hundred characters, with no three-item preference. Saved versions retain their original content. Structural tests and semantic evaluation against known source facts are separate checks; shorter output alone is not evidence of better selection.

Insights appear in the same stream as colored Apple-style cards, without separate default/custom tabs. Structured live and post-meeting summaries show all five parts directly, without a disclosure step or enclosing summary card. User-created insights take priority above Overview; Meeting Insights appears last after End. Custom and meeting insights have no Details screen or generated supporting quotes. Each historical or unsaved version renders its own content shape even if the prompt changed between generations.

End preserves live history but does not request a summary. Generate in Meeting Insights explicitly sends one combined full-meeting request guided by the current definitions. Regeneration appends another version. Empty placeholders are distinct from a generated finding that nothing was recorded. Unknown owners/dates remain unknown, and suggestions are presented as proposals rather than agreements.

Export includes every saved result version, its parts and cutoff, provisional disclosure, and the original/refined transcript. The overall summary conclusion remains in export. Transcript refinement never overwrites original source. Title generation is a separate optional request and follows the user-title protection in Section 2. Refinement and title tasks belong to the meeting, continue across switching and view recreation, and save only to that original meeting. Sidebar activity remains visible while work is queued or running; returning to a meeting retains its progress and errors. Successful deletion invalidates its tasks. Completed results persist, but unfinished requests do not resume after app exit.

## 6. Context, privacy, and failure policy

All insight kinds receive complete original source through their cutoff and complete applicable meeting/personal vocabulary. Historical analysis ignores the Original/Refined display toggle. Earlier AI results and attachments are not factual context for insights in V2.

Model context window (tokens) in AI Services defaults to 1,000,000; supported configuration is 16,384–2,000,000. Save applies it to new insight requests; queued/active inputs and saved versions retain their frozen value. Preflight conservatively counts serialized bytes, instructions, schema, 1,024 bytes of framing allowance, and an 8,192-token output allowance. This is an estimate, not model-limit discovery or tokenization. Oversized full input fails locally before sending without truncation, separately from provider errors. No compressed or recent-only fallback is implemented. Titles retain their independent recent 6,000-character budget.

Local capture, Speech, Translation, and history work without AI. Audio is neither stored nor uploaded. Optional AI uses the saved user-configured service and strict JSON Schema responses. Transcript and Markdown are untrusted analyzed data and cannot override the response contract or initiate external actions. Refinement includes saved personal vocabulary; title generation includes none.

AI configuration drafts are distinct from saved preferences. Connection tests and model discovery belong to the draft; editing connection details or dismissing Settings invalidates their pending replies and releases loading state. A discovered model list cannot overwrite a model typed while it was loading. Cancelling these configuration checks does not cancel vocabulary extraction.

Database-open failure blocks meeting work with a visible error instead of silently switching to memory storage. Persistence errors are reported, and earlier saved results remain available. Obsolete single-insight storage, old UI routes, compatibility readers, dual writes, and custom migrations are absent. Existing user data files are not manually deleted.

## 7. Resolved choice index

The original P2-O identifiers remain useful for tracing discussion to the accepted contract; they are no longer open implementation questions.

| ID | Resolution |
|---|---|
| P2-O01 | Managed UTF-8 Markdown copies, explicit removal, shared vocabulary interaction; no document-grounded insights. |
| P2-O02 | Separate meeting/personal stores; meeting spelling wins; ASR freezes at Start/Resume and each AI input retains its vocabulary. |
| P2-O03 | 45 seconds plus 80 characters; one automatic request within six total insight requests. |
| P2-O04 | Manual provisional text is marked separately and retained exactly; automatic input is finalized-only. |
| P2-O05 | Full original source with configurable budget and explicit preflight rejection; no compression. |
| P2-O06 | One structured result schema; analytical focus changes instructions, not source coverage. |
| P2-O07 | Edits affect the next request; existing requests/results retain their input. |
| P2-O08 | Cancel on insight lifecycle boundaries, reject stale owners/tokens, retain unsaved output for local retry. |
| P2-O09 | Explicit combined meeting-wide summary after End, using original source. |
| P2-O10 | Colored cards, per-insight version selection and retained expansion; no pruning or pins. |
| P2-O11 | Core release only; Details/supporting-quote generation removed and extensions below deferred. |

## 8. Deferred extensions

| ID | Deferred capability |
|---|---|
| P2-C01 | Meeting goals and a must-ask checklist |
| P2-C02 | Evidence navigation to transcript/document passages |
| P2-C03 | A dedicated cumulative decision/change ledger beyond full-context regenerated insights |
| P2-C04 | Reusable meeting templates |
| P2-C05 | Copy preparation or carry unresolved questions into another meeting |
| P2-C06 | Lightweight live markers |
| P2-C07 | Editable follow-up drafts and any external sending workflow |
| P2-C08 | Document-grounded insights with retrieval, budget management, and attribution |
| P2-C09 | Cross-meeting projects or reusable context |
| P2-C10 | Saved-result pinning |

These capabilities are not part of the V2 merge. Rationale for adopted architecture is in [DECISIONS.md](DECISIONS.md); operational details are in the [documentation index](README.md).
