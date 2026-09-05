# AI Insights and Transcript Refinement

> Main implementation: [`InsightEngine.swift`](../Sources/Insights/InsightEngine.swift), [`TranscriptRefiner.swift`](../Sources/Insights/TranscriptRefiner.swift), [`MeetingTitleGenerator.swift`](../Sources/Insights/MeetingTitleGenerator.swift), [`VocabularyGenerator.swift`](../Sources/Insights/VocabularyGenerator.swift), [`VocabularyImportController.swift`](../Sources/Capture/VocabularyImportController.swift), [`VocabularyImportWindow.swift`](../Sources/Capture/VocabularyImportWindow.swift), [`InsightModels.swift`](../Sources/Insights/InsightModels.swift), [`LLMProvider.swift`](../Sources/AI/LLMProvider.swift), [`OpenAICompatibleProvider.swift`](../Sources/AI/OpenAICompatibleProvider.swift), [`AISettings.swift`](../Sources/AI/AISettings.swift).

## 1. Capability boundaries

AI is an optional enhancement, independent of live-caption correctness:

- Without an API key, capture, ASR, local translation, saving, and export still work.
- Configured AI sends transcript text to the selected provider.
- Explicit Markdown vocabulary generation sends selected file contents in batches, without filenames. Content, excerpts, and unsaved candidates remain in the current window's memory; explicitly saved terms enter local vocabulary.
- User-initiated refinement sends the complete saved vocabulary. Insights send only terms matched in recent context; titles send none.
- This pipeline never uploads audio.

AI Services settings is shared by insights, refinement, titles, and Markdown vocabulary generation. Insights is a consumer, not the owner or proxy for other features' configuration. Complete, saved configuration enables each feature's existing triggers; there is no additional enable switch.

Shared configuration, provider, strict parsing, and settings UI live in `Sources/AI/`. `Sources/App/SettingsView.swift` owns the window and navigation. `AppDelegate` injects one `AISettings` into all consumers; UI reads availability directly from it, not through `InsightEngine`.

App-owned prompts are English. Insights and generated titles request English output. Refinement preserves the meeting's selected source/target languages, and vocabulary extraction preserves original term spelling.

## 2. Minimal provider abstraction

[`LLMProvider`](../Sources/AI/LLMProvider.swift) has one method:

```swift
func complete(system: String, user: String, schema: LLMResponseSchema) async throws -> String
```

All built-in providers use OpenAI-compatible `/chat/completions` Structured Outputs, so there is one `OpenAICompatibleProvider`. Callers own business schemas; the provider encodes them into requests.

Built-in models are Qwen `qwen3.8-flash` and Kimi `kimi-k3`, with confirmed strict Schema support, plus custom OpenAI-compatible endpoints. Old DeepSeek and GLM JSON Object paths were removed.

HTTP behavior:

- Nonstreaming.
- All generation requests use a 60-second timeout: vocabulary, insights, refinement, titles, and connection tests. Vocabulary retries retain this timeout, serial execution, and at most two retries. Model discovery uses 30 seconds.
- `temperature=0.3`, capped where a provider requires it.
- Every request requires `response_format: {type: "json_schema", json_schema: {strict: true, ...}}`.
- Check `finish_reason`; distinguish truncation, refusal, HTTP 400 schema/parameter errors, other HTTP errors, network failures, parsing, and empty content as readable `LLMError` values.

## 3. One insight model, three uses

[`InsightResult`](../Sources/Insights/InsightModels.swift) defines:

1. The strict JSON Schema sent to the model.
2. SwiftUI card data.
3. The payload persisted in `MeetingRecord.insightJSON`.

Fields are topic, suggestions, suggested answer, action items, and decisions. Every key is required. No answer is `null`; other empty content uses empty strings/arrays. Missing fields, wrong types, or more than three suggestions reject the entire response.

The UI renders typed cards directly, without a Markdown/HTML renderer.

## 4. Live insight triggers

Only final ASR drives generation, not interim:

- A speaker switch, or
- Six accumulated new final sentences.

Input contains the latest complete `sourceText` lines formatted as `Me: ...` / `Other party: ...`. The budget is 6,000 Swift characters, reserving room for prompt/output in the smallest built-in 8K context. If one line exceeds the budget, keep its latest suffix. Live translations are not treated as facts, avoiding amplified translation errors.

At each live/historical request, `InsightEngine` matches saved vocabulary against this truncated recent context. Matching is case-insensitive; terms beginning/ending in letters or digits also require alphanumeric boundaries, so `PR` does not match `project`. Only matches enter the system prompt, preserving saved order and exact spelling. The model may use that spelling when relevant, without introducing absent information. Empty vocabulary or no matches adds no prompt section.

### 4.1 One in-flight request with a dirty flag

`InsightEngine` permits one request at a time:

- Changes during generation set `dirtyDuringGen=true`.
- Completion can immediately schedule at most one latest complete snapshot.
- Each intermediate change does not enqueue a separate request.

Like the translation mailbox, this prioritizes the latest state over replaying intermediate snapshots.

Every live generation also carries `liveToken`. A new meeting/reset cancels work and replaces the token; even a late provider response cannot update the next meeting's cards.

## 5. Historical insights

When viewing history:

- Show cached insights immediately.
- Allow manual generation/regeneration.
- Prefer nonempty `refinedSource` per line, otherwise `sourceText`; translations are never factual input. Live insights and titles still use original `sourceText`.
- Persist results to `insightJSON` for reuse without another request.
- Prepend insights to exported Markdown.
- Cancel generation on selection changes or deletion. Recheck selection and operation token before persistence to reject stale results.

Live insights are not automatically stored in `MeetingRecord.insightJSON` at session end. Historical caches come from explicit historical generation.

## 6. Post-meeting refinement

Refinement cleans ASR source line by line and retranslates in the original direction when languages differ. Independent [`TranscriptRefiner`](../Sources/Insights/TranscriptRefiner.swift) owns this use case; `InsightEngine` owns structured insights only. They share provider settings, not state machines.

Starting refinement also starts a separate [`MeetingTitleGenerator`](../Sources/Insights/MeetingTitleGenerator.swift) HTTP request. Titles do not join the batch state machine or wait for refinement.

### 6.1 Batching

- At most eight lines and approximately 1,500 characters per batch.
- Serial execution limits output size and service load.
- Include the previous batch's last two lines as read-only context.
- Freeze saved vocabulary at operation start and use it for every batch; mid-operation settings edits cannot change later batches.
- Carry the accumulated glossary forward for consistent terminology.

### 6.2 Language behavior

- Different languages: explicitly name source and target, conservatively clean source, and regenerate target in the selected direction using context.
- Matching languages: explicitly prohibit translation, clean source only, and let the caller mirror it to refined target.
- Vocabulary corrects source spelling only when supported by the conversation. Existing glossary target mappings take precedence; brands, products, people, and acronyms without established translations keep their original form.
- Input speaker labels provide context only. If the model echoes Me/Other party or their Chinese equivalents followed by a colon into source/target, the parsing boundary strips that leading label before persistence. Ordinary first-person prose is unaffected.

Both prompts explicitly prohibit invented facts.

### 6.3 Partial success

Each batch fails independently:

- Skip failed batches and retain their original text.
- Preserve other successful batches.
- Fail the whole operation only if every batch fails.

Write results by `orderIndex` into `refinedSource/refinedTarget`. This additive design preserves access to originals and makes incomplete refinement usable.

Changing records invalidates both the view task and the refiner's run token. A returning provider must pass cancellation, run-token, and selected-record-ID checks before modifying SwiftData.

### 6.4 Meeting titles

- Use chronologically ordered ASR source, with the latest 6,000-character budget, allowing parallel refinement.
- Use the independent `meeting_title` Schema. The English prompt names the field and asks for a specific title of 3–8 words and at most 60 characters. The client rejects blank titles and caps unexpectedly long output at 60 characters.
- Title/refinement outcomes and saves are independent. Failure in one does not invalidate success in the other.
- Generate only without a valid `aiTitle`. After successful persistence, Refine Again skips title generation. A previously failed title is retried on the next refinement.
- Selection changes cancel both tasks; each checks operation token and current record ID before writing.
- Persist success in `MeetingRecord.aiTitle`. Sidebar/details prioritize it while retaining start time; missing titles display start time.

### 6.5 Shared JSON boundary

Insights, refinement, titles, and connection tests use strict `JSONResponseParser`: decode the entire assistant content with `JSONDecoder`, without extracting code fences, surrounding text, or tolerating missing fields. Every request still sends strict Schema. Prompts also briefly describe field semantics so gateways that accept but ignore `response_format` can produce valid structure. This is not a JSON Object fallback: invalid responses fail entirely with a distinct schema-contract error.

## 7. Configuration and secrets

- Provider ID, custom API URL, and custom model are stored in UserDefaults.
- API keys are Keychain generic passwords under bundle-ID service `com.plus.samewave`. Older app-identity settings/keys are not read or migrated. The English display-name change keeps this namespace.
- Settings uses drafts; only Save updates shared configuration.
- AI Services explains its app-wide purpose. Configuration actions in insights, refinement, and vocabulary select this tab even when Vocabulary was active, without submitting vocabulary drafts. Custom settings scroll while Save/Cancel stay fixed at the bottom.
- `AISettings` validates both saved settings and connection-test drafts: every provider needs a nonblank key; custom providers also need a valid URL and nonblank model ID. Existing UserDefaults keys and Keychain accounts remain the sole storage, without copies or migrations.
- A draft can run a representative connection test containing nested objects and arrays, verifying the actual contract instead of accepting an accidentally valid simple object.
- Custom URLs accept bare domains/hosts, versioned base URLs, or complete `/chat/completions` endpoints. Remote bare hosts default to HTTPS and `/v1/chat/completions`; localhost/loopback default to HTTP. The UI shows the normalized request URL.
- Fetch model lists from sibling `/models` with the same Bearer key. Successful results populate a menu while keeping manual model entry. A 404/405, empty list, or nonstandard response does not block configuration.
- ATS explicitly allows local networking only; external services require HTTPS.
- Vocabulary is a separate tab. Local English recognition uses it; refinement uses the complete operation-start snapshot; live/history insights use matches only; titles use none. Empty vocabulary/matches add no insight prompt content.
- Generate from Markdown opens the system file picker first and a separate window only after selection. Cancelling the initial picker starts nothing. Switching tabs or closing Settings does not affect work. Closing the generation window cancels requests and discards unsaved review content; Stop cancels current/pending requests while retaining the window and candidates, or returns to file selection if none exist. Actual NSWindow close notifications define cancellation; state changes and hiding do not.
- Input may contain multiple UTF-8 `.md`/`.markdown` files, limited to 3 MB each and 30 MB total, with no total body-character cap. Local fragments of at most 18,000 characters assemble into actual requests of at most 20,000 characters. Requests are serial, retry twice after the first failure, and continue after exhausted failures. Each success returns at most 50 single-line terms through its own strict Schema. Markdown is untrusted data; the system prompt forbids following embedded instructions. Candidates must pass both specific-named-entity and speech-recognition-value gates. Generic concepts, categories, process terms, and phrases distinguished only by heading style or capitals are excluded; uncertainty favors fewer or no terms.
- Publish each success immediately after deduplicating against saved vocabulary, the current draft, and previously seen terms. Review defaults to selected, supports edits and Select All/Deselect All, and expands local filenames/excerpts. Missing source matches explicitly require verification. Stable candidate IDs and original extraction identity prevent later requests from resetting edits/selections.
- Add and Save persists only selected new terms after another deduplication. Append only new terms to the draft while retaining other manual edits and formatting. Saving works during generation and reports inline.
- Each request retains succeeded/failed/pending state. Retry Incomplete Requests reruns failed, interrupted, and unsent requests, each with a fresh initial attempt plus two retries. Successful requests are not charged again. Edits, sources, and attempt history remain. Provider configuration freezes at the original start and does not change on retry. Stop invalidates the run token; late responses cannot enter review. Restart waits for old cancellation to preserve serial execution.
- Default progress shows completed count, new-term count, and current retry state. Request Details records each success/error/stop and duration. A monotonic clock measures from immediately before provider invocation through complete response and term validation, excluding retry delay. This combines network/server time and cannot isolate inference, server queues, or network latency. Reading/splitting happens in the background with propagated cancellation.

## 8. Risks and limitations

- The app neither sets nor discovers a model's context window. Server/model configuration controls it. Insights/titles budget 6,000 characters; Markdown request bodies budget 20,000. Characters are not tokens, and full requests also include prompts, schemas, and output.
- `/chat/completions` compatibility does not guarantee enforced `json_schema`. Custom services should pass the representative connection test. Production requests always send Schema and decode strictly; gateways that ignore it can still fail intermittently.
- `/models` is optional and may use a different gateway path; manual model IDs remain necessary for such services.
- Strict Schema does not guarantee factual correctness. Clients still validate titles, batch line IDs, suggestion counts, and other business invariants.
- Speaker switches can trigger frequent live insights. Single-flight coalescing prevents backlog but supplies no cooldown or spending budget.
- Long Markdown creates multiple requests with corresponding latency/cost. Requests failing all three attempts are skipped, so review may cover only part of the documents; the window discloses this.
- Matched vocabulary can contain internal project or personal names and is sent in the insight system prompt.
- Users must understand the cloud boundary. “Fully offline” applies only to live captions with AI unused.
