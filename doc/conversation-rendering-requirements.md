# Live Meeting Conversation Rendering Requirements

> Current contract for one-on-one system-audio and microphone captions. See [the pipeline reference](02-live-captions-and-translation.md), [DEC-20260917-002](DECISIONS.md#dec-20260917-002), and [DEC-20260917-003](DECISIONS.md#dec-20260917-003).

## 1. Speaker symmetry and immediate feedback

- Either speaker's first nonempty lexical ASR interim or final opens a Section immediately, including short acknowledgments.
- Each speaker has at most one open draft caption. Continuous overlap can grow both drafts; a recognizer may hold an unfinished hypothesis spanning several independently translated Sections.
- IDs and display order follow the first observed text growth that opens each Section. Final recognition and translation never reorder them.
- Capture channels define identity: microphone is You, system audio is Speaker. Multiple remote people share the system-audio identity.

## 2. Turn boundaries and cumulative recognition

- Remote → mine → remote must produce three ordered paragraphs when remote resumes after at least one second without added recognition text. No final callback is required. Apply the same rule with identities reversed.
- A cumulative hypothesis retains existing words in their original Sections. Newly added trailing words refresh recognition activity. They stay in the active paragraph during continuous overlap; after a one-second gap they open a later turn if another speaker intervened. Never copy the earlier prefix into that turn.
- Spelling, case, punctuation, and middle-word corrections update owned fragments without taking the floor or refreshing activity. A final corrects and commits every owned fragment once, including fragments in sealed Sections.
- Sealing closes a display turn to added speech, while allowing corrections to its existing words. It must not promote, discard, or clear the recognizer's unfinished hypothesis.
- Retraction removes an empty fragment and its translation. Do not reuse its ID or allow late results to recreate it.
- Prefer confirmed sentence and sufficiently long clause boundaries, with the word/character guard defined in the pipeline reference. Count committed and interim source together. ASR finality commits source once and confirms eligible boundaries; short unpunctuated finals continue within the active unit on the next hypothesis. Sentence-ended finals seal immediately.
- Confirm a punctuation prefix after 700 ms unchanged, independently of translation. Suffix growth, duplicate callbacks, and other-speaker updates cannot extend its deadline. Removed or revised punctuation cancels or replaces the candidate. The size guard can force an earlier decision, preferring available natural boundaries.
- Sealing an unchanged unit retains its ID and visible target. An internal split of the newest active unit retains the head ID and moves only the suffix to a new unit. Preserve source and recognition ownership once, and invalidate every target/request that covered the old combined unit. Never move existing words across another speaker's newer Section. These operations do not finalize the recognizer hypothesis.
- Pause/end drains ASR, then preserves any remaining interim fragments alongside earlier committed source, exactly once.
- Empty or nonlexical callbacks neither create a Section nor interrupt someone else.

Interim English Speech results can have only whole-hypothesis timing. Word alignment and a monotonic one-second inactivity rule therefore define observed recognition turns, not acoustic VAD. Delayed/batched results can shift boundaries; wholesale rewrites and tokenization changes can blur corrections versus added speech. Inactivity without an intervening speaker does not split the latest paragraph.

## 3. Caption presentation and independent translation

- In the full workspace, group adjacent same-speaker translation units into continuous paragraphs with one speaker/time header. New units start another paragraph at the source-length, speaker, or time-gap boundaries in the pipeline reference. Existing live membership does not change after a source revision, translation, or promotion. Retractions remove only their own spans. Existing history uses the same rule on original source; Original/Refined cannot alter group boundaries or overwrite stored content.
- In the full workspace, never show Translating text or a translation spinner. Before the first translation returns, show source as the primary paragraph once and reserve the secondary row. A unit with a target uses that target as its primary span; a missing or failed target uses source. Once any translation differs from source, show the complete original paragraph beneath it. Draft spans use secondary text color; submission retains the same span and translation. At a fixed width, translation revisions and submission must not shrink the live primary block or whole paragraph. History uses natural height.
- Source segmentation never waits for translation. Open and sealed Sections can both have pending or completed translation.
- Translate changed source snapshots only, using exactly the current unit's source without preceding context or delimiter recovery. Identical interims, finals, and sealing must not invalidate useful work. Corrections spanning several Sections schedule all affected fragments. After an internal split, source remains visible until each new fragment's translation returns; obsolete combined results must never reappear.
- Display each completed result that advances the displayed generation, even when newer source is queued. Never replace a newer displayed result with an older completion.
- Mark the internal state done only when the latest requested snapshot completes. A later source update returns the internal state to translating without a visible busy label.
- In the full workspace, a failed or empty translation shows source with an explicit failure label. Restored missing translations do not pretend work is running.
- Same-language captions bypass Translation and suppress duplicate source text.
- New speech after a confirmed boundary must not retranslate or replace the preceding caption. A source correction schedules only captions whose source actually changed.
- Follow content-height growth while the reader is near the bottom. Same-height revisions must not scroll. Reading history suspends following until the reader returns to the bottom.
- In saved history, scrolling unchanged content must preserve document height and the requested reading offset. Verify long mixed-height paragraphs in Original and Refined modes, repeated direction changes, and narrow/wide windows. Text or width changes may reflow the document; scrolling alone must not.
- Opening and switching long saved transcripts must retain the complete document and native text selection/copy. The local 500-Section bilingual benchmark requires opening and each Original/Refined change, including complete layout, to finish within 500 ms. Check every Section and the last glyph; deferred or omitted content cannot satisfy the timing requirement. Already-mounted history must observe arriving refinement and saved-line changes, and switching to shorter or empty records must replace old text and clamp the scroll extent.

Simple Mode uses the full workspace's `CaptionsView` to show every caption, with the same paragraph grouping, bilingual text, Speaker/You labels, typography, translation states, height reservation, and scrolling behavior. Source remains readable while translations are pending or unavailable; same-language sessions show recognized source once. Reading earlier captions suspends automatic scrolling, and returning to the bottom resumes following. Session and translation ownership survive every mode switch; the complete conversation remains available in both presentations and saved history.

The floating panel has no traffic-light buttons or language selectors. Its meeting actions are microphone on/off, pause/resume, end, and return to the full window. Header and menu entries exist only while a session is active, including pauses and resource transitions. Preparation, empty workspaces, and ended history have no entry or mode shortcut. Successful End or startup failure returns to the retained full window; a failed final save keeps the paused session and panel available for retry. Capture actions are disabled during resource transitions; languages and new meetings are configured in the full window. Background opacity ranges from 0% to 100%, defaults to 85%, and persists as a presentation preference. Changing it leaves text and control opacity unchanged.

## 4. Scheduling and lifecycle

- Make a caption's first request eligible after 60 ms, then space its subsequent dispatches by at least 400 ms. Retain the newest pending snapshot without extending its original deadline, FIFO fairness, and one active request. Never drop another caption to bound the queue. Preparation, queueing, and service execution add their own latency.
- Reject callbacks from an older meeting or replaced translation consumer.
- Consumer cancellation must not poison the wake-up mechanism for the next language pair/session. Preparation failure also settles requests arriving after failure.
- Bound prepared translation requests to 15 seconds. A deadline failure settles work, cancels the session, and rejects late results. Model preparation/downloads remain a separate phase.
- Start/resume prepares a fresh Translation session. Pause/end waits up to five seconds for queued work after draining recognition, then preserves source and reports incomplete work where applicable.

## 5. Required interruption walkthrough

| Event | Ordered visible paragraphs |
|---|---|
| Remote interim: “The release is ready” | Speaker: “The release is ready” |
| My interim: “I have a question” | Speaker: “The release is ready”; You: “I have a question” |
| Remote interim after a one-second gap: “The release is ready for review” | Speaker: “The release is ready”; You: “I have a question”; Speaker: “for review” |
| Remote final: “The release was ready for review.” | Correct the first paragraph to “The release was ready” and the third to “for review.”; keep three paragraphs |
| My late final: “I had a question.” | Correct the second paragraph once; keep order and current floor |
| Pause/end | Drain final results and preserve every remaining fragment |

Repeat with both identities reversed, repeated interruptions, repeated words, a short finalized reply, and Chinese source. Dense alternating growth must retain two active drafts and split only at caption boundaries; pure revisions must not acquire the floor or extend activity. A return after recognition inactivity must form a new caption after the interrupter. Translation completion does not change ordering or recognition ownership.

## 6. Repeatable validation

`CaptionStoreTests` and `CaptionStabilityTests` exercise production transitions, including a controlled monotonic clock, dense simultaneous growth, replayed native English cumulative snapshots, short final continuation, retractions, withdrawn/late punctuation, prefix deadlines during suffix growth, bounded unpunctuated speech, Chinese, split ownership and stale-result rejection, translation scheduling, and stop/restore. `CaptionParagraphTests` checks the reported seven-fragment history, length/speaker/time boundaries, stable membership under corrections/retractions, joining, and refinement independence. `TranslationBridgeTests` covers first-request responsiveness, sustained-input cadence and coalescing, fairness, cancellation/restart, preparation failure, empty/error responses, timeout, and stale replies. Native rendering and `CaptionPresentationTests` verify continuous live/history paragraphs, stable earlier words and source positions, progressive/completed/failed states, promotion geometry, reading history, and return to bottom. Persistence/export tests retain source and caption order across interim autosaves, short finals, late splits, and finalization.

`HistoryPerformanceTests` measures native opening and mode changes with complete 500-Section layout and content assertions. `HistoryTranscriptTests` verifies SwiftData observation while mounted, native selection/copy, equal-update reading state, source echoes, and shorter/empty record replacement. These use production views and platform text controls. Timing varies by machine and process load; the local threshold is a regression gate, not a universal latency guarantee.

Real capture latency, Speech model accuracy, and Apple Translation speed remain platform-dependent signed-app smoke checks; deterministic tests validate state and scheduling rather than those services' quality.
