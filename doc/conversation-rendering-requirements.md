# Live Meeting Conversation Rendering Requirements

> Current contract for one-on-one system-audio and microphone captions. See [the pipeline reference](02-live-captions-and-translation.md) and [DEC-20260907-004](DECISIONS.md#dec-20260907-004).

## 1. Speaker symmetry and immediate feedback

- Either speaker's first nonempty lexical ASR interim or final opens a Section immediately, including short acknowledgments.
- Each speaker has at most one open display turn. Continuous overlap can grow both turns; a recognizer may hold an unfinished hypothesis spanning several Sections.
- IDs and display order follow the first observed text growth that opens each Section. Final recognition and translation never reorder them.
- Capture channels define identity: microphone is You, system audio is Speaker. Multiple remote people share the system-audio identity.

## 2. Turn boundaries and cumulative recognition

- Remote → mine → remote must produce three ordered paragraphs when remote resumes after at least one second without added recognition text. No final callback is required. Apply the same rule with identities reversed.
- A cumulative hypothesis retains existing words in their original Sections. Newly added trailing words refresh recognition activity. They stay in the active paragraph during continuous overlap; after a one-second gap they open a later turn if another speaker intervened. Never copy the earlier prefix into that turn.
- Spelling, case, punctuation, and middle-word corrections update owned fragments without taking the floor or refreshing activity. A final corrects and commits every owned fragment once, including fragments in sealed Sections.
- Sealing closes a display turn to added speech, while allowing corrections to its existing words. It must not promote, discard, or clear the recognizer's unfinished hypothesis.
- Retraction removes an empty fragment and its translation. Do not reuse its ID or allow late results to recreate it.
- Adjacent utterances by one speaker share a Section until six fragments are committed. Split before the next utterance and freeze same-speaker context, including previous unfinished source.
- Pause/end drains ASR, then preserves any remaining interim fragments alongside earlier committed source, exactly once.
- Empty or nonlexical callbacks neither create a Section nor interrupt someone else.

Interim English Speech results can have only whole-hypothesis timing. Word alignment and a monotonic one-second inactivity rule therefore define observed recognition turns, not acoustic VAD. Delayed/batched results can shift boundaries; wholesale rewrites and tokenization changes can blur corrections versus added speech. Inactivity without an intervening speaker does not split the latest paragraph.

## 3. Caption presentation and independent translation

- Never show Translating text or a translation spinner. Before the first translation returns, show source as the primary caption once. When available, show translated text above distinct secondary source.
- Source segmentation never waits for translation. Open and sealed Sections can both have pending or completed translation.
- Translate changed source snapshots only. Identical interims, finals, and sealing must not invalidate useful work. Corrections spanning several Sections schedule all affected fragments.
- Display each completed result that advances the displayed generation, even when newer source is queued. Never replace a newer displayed result with an older completion.
- Mark the internal state done only when the latest requested snapshot completes. A later source update returns the internal state to translating without a visible busy label.
- A failed or empty translation shows source with an explicit failure label. Restored missing translations do not pretend work is running.
- Same-language captions bypass Translation and suppress duplicate source text.

## 4. Scheduling and lifecycle

- Coalesce pending snapshots per Section and retain FIFO fairness across Sections under one active request.
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

Repeat with both identities reversed, repeated interruptions, repeated words, a short finalized reply, and Chinese source. Dense alternating growth must keep two readable paragraphs; pure revisions must not fragment turns or extend activity. A return after recognition inactivity must form a new paragraph after the interrupter. Translation completion does not change ordering or recognition ownership.

## 6. Repeatable validation

`CaptionStoreTests` exercises these transitions through production logic, including a controlled monotonic clock, dense simultaneous growth, replayed native English cumulative snapshots, retractions, sentence limits, frozen context, translation scheduling, and stop/restore. `TranslationBridgeTests` covers dense input, fairness, cancellation/restart, preparation failure, empty/error responses, timeout, and stale replies. Native rendering tests verify source before translation, three chronological paragraphs, progressive/completed/failed states, and absence of Translating. Persistence/export tests retain source and turn order across interim autosaves and finalization.

Real capture latency, Speech model accuracy, and Apple Translation speed remain platform-dependent signed-app smoke checks; deterministic tests validate state and scheduling rather than those services' quality.
