# Live Meeting Conversation Rendering Requirements

> Current contract for one-on-one system-audio and microphone captions. See [the pipeline reference](02-live-captions-and-translation.md) and [DEC-20260907-003](DECISIONS.md#dec-20260907-003).

## 1. Speaker symmetry and immediate feedback

- Either speaker's first nonempty ASR interim or final opens a Section immediately, including short acknowledgments.
- One unfinished Section per speaker may remain open during overlap. Both speakers' source text updates without waiting for the other's final result or translation.
- IDs and display order follow the first observed result that opens each Section. Do not reorder Sections when final recognition or translation arrives.
- Capture channels define identity: microphone is You, system audio is Speaker. Multiple remote people share the system-audio identity.

## 2. Utterance ownership and interruption

- A speaker's interim revisions and final result belong to the same unfinished utterance. The final replaces its interim tail without duplicating the hypothesis.
- If the other speaker opens a later Section during that utterance, keep the interrupted Section open for its remaining ASR revisions and final. Seal it when the final arrives; its next utterance opens a new Section after the interruption.
- If the previous speaker has already committed their utterance, the new speaker's first result seals the previous Section immediately.
- Adjacent utterances by one speaker share a Section until six sentences are committed. Split before the next interim or direct final, preserving translation context.
- Pause/end finalizes ASR and seals both speakers. If ASR leaves a partial tail, preserve it alongside any earlier committed sentences.
- Empty interim callbacks neither create a Section nor interrupt someone else.

The pipeline has ASR interim/final callbacks, without acoustic speech-start/end or continuous VAD. Do not infer word-level interruption boundaries from revised text or split every alternating partial. No sealed-source correction or duplicated interim-promotion path is required.

## 3. Independent translation progress

- Source segmentation never waits for translation. Open and sealed Sections can both be translating or done.
- Translation begins for changed source snapshots only. Identical interims, finals, and sealing must not invalidate useful work.
- Display each completed result that advances the displayed generation, even when newer source is queued. Never replace a newer displayed result with an older completion.
- Mark done only when the latest requested snapshot completes. A later source update returns to translating.
- A failed or empty translation shows source with a failure state. A missing translation after restore must not show perpetual work in progress.
- Same-language captions bypass Translation and suppress duplicate source text.

## 4. Scheduling and lifecycle

- Coalesce pending snapshots per Section and retain FIFO fairness across Sections under one active request.
- Reject callbacks from an older meeting or replaced translation consumer.
- Consumer cancellation must not poison the wake-up mechanism for the next language pair/session. Preparation failure must also settle requests arriving after failure.
- Bound prepared translation requests to 15 seconds. A deadline failure settles work, cancels the session, and rejects late results. Model preparation/downloads remain a separate phase.
- Start/resume prepares a fresh Translation session. Pause/end waits up to five seconds for queued work after draining recognition, then preserves source and reports incomplete work where applicable.

## 5. Required overlap walkthrough

| Event | Sections and visible source |
|---|---|
| Remote interim | Section 0 opens with remote source |
| My interim | Section 1 opens immediately; Section 0 remains available for its unfinished utterance |
| Alternating revisions | Sections 0 and 1 update in place; no duplicate Sections |
| Remote final | Section 0 receives the corrected final once and seals |
| Remote continuation interim | Section 2 opens after Section 1 with frozen remote context |
| My late final | Section 1 receives its corrected final once and seals |
| Pause/end | All final results drain, remaining tails survive, and both speakers seal |

Reverse the speaker identities and require identical behavior. Translation may complete between any of these events without changing the Section ordering or ASR ownership.

## 6. Repeatable validation

`CaptionStoreTests` covers symmetric overlap, late finals, continuation order, source retention, six-sentence splitting, duplicate snapshots, progressive translation, failure, and restore. `TranslationBridgeTests` covers dense input, fairness, idle/in-flight cancellation, preparation failure, empty/error responses, timeout, restart, and stale replies. Native rendering tests verify both speakers and progress/failure labels. Persistence tests verify that interim autosaves become final source without duplicate rows.

Real capture latency, Speech model accuracy, and Apple Translation speed remain platform-dependent signed-app smoke checks; deterministic tests validate state and scheduling rather than those services' quality.
