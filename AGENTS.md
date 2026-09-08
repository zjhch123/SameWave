# AGENTS.md — SameWave

## Scope

- These instructions apply to the entire `SameWave` repository. Source, documentation, and project declarations use paths relative to the repository root, independent of any surrounding workspace layout.
- SameWave is a native Swift 6 app for macOS 26+: SwiftUI/AppKit UI, ScreenCaptureKit/AVFoundation audio, local Apple Speech recognition, local Translation, SwiftData history, and optional OpenAI-compatible insights.
- Run `git status --short` before making changes. The workspace may contain user edits; do not overwrite, revert, or tidy unrelated changes.
- Read [`MEMORY.md`](MEMORY.md) at the start of each task and follow its project preferences and continuing authorizations.

## References

- [`doc/`](doc/) contains project documentation; [`doc/README.md`](doc/README.md) is its index. References provide context, not compatibility contracts. Judge behavior against current source, `project.yml`, and explicit requirements. If a reference conflicts with implementation, establish actual behavior and update the relevant documentation within task scope; do not retain obsolete code to match old prose.
- Read the references needed for the task, rather than loading the entire directory indiscriminately:

| Task area | Read first | Then verify |
|---|---|---|
| Product, layers, module responsibilities | [Product and architecture](doc/01-product-and-architecture.md) | `project.yml`, relevant entry points and call chains |
| Audio, ASR, Sections, translation | [Live captions and translation](doc/02-live-captions-and-translation.md) | [Conversation rendering requirements](doc/conversation-rendering-requirements.md), `Sources/Meeting/CaptionStore.swift`, `Sources/Meeting/CaptureCoordinator.swift` |
| Start, pause, resume, history, export | [Session lifecycle and data](doc/03-session-lifecycle-and-data.md) | `Sources/Meeting/CaptureCoordinator.swift`, `Sources/History/MeetingHistory.swift`, `Sources/History/TranscriptExporter.swift` |
| Insights, providers, prompts, refinement | [AI insights and refinement](doc/04-ai-insights-and-refinement.md) | `Sources/Insights/InsightEngine.swift`, `Sources/Insights/InsightModels.swift`, provider/settings files |
| Architectural tradeoffs, evolution, boundaries | [Design, evolution, and boundaries](doc/05-design-evolution-and-boundaries.md) | Current working tree, requirements, reproducible evidence |
| Build, permissions, change entry points, validation | [Development and validation](doc/06-development-and-validation.md) | `project.yml`, `build.sh`, current environment |
| Accepted decisions and their rationale | [DECISIONS.md](doc/DECISIONS.md) | Relevant requirements, implementation, tests, latest references |

## Engineering principles

- Do not preserve backward compatibility. When requirements replace a path, remove obsolete implementations, switches, and dead code. Do not add fallbacks, dual writes, adapters, or migration branches.
- Choose the simplest complete implementation that meets current requirements. Avoid speculative protocols, configuration, factories, service locators, and abstractions with a single implementation.
- Grow in layers: preserve a buildable, runnable vertical slice before adding capability. Do not replace a working product with unfinished architecture.
- Keep responsibilities clear: Views render, Stores own state, Coordinators orchestrate, capture/ASR/providers own I/O boundaries, and persistence writes data.
- Prefer existing project capabilities and public Apple frameworks. Check current framework/dependency documentation and types before adding a dependency. Add a mature library only when it substantially reduces complexity, and explain why.
- Make maintainable long-term architectural decisions, not temporary solutions intended for replacement.
- Follow Swift API Design Guidelines; prefer value types, explicit state, and structured concurrency. Do not hide concurrency problems with `@unchecked Sendable`, `nonisolated(unsafe)`, or disabled checks. Do not spread existing exceptions without evidence.
- Preserve and present errors at the correct boundary. Do not use empty `catch` blocks, unexplained `try?`, false success states, or swallowed build exit codes.
- Keep source localization keys, prompts, export templates, and documentation in English. App-owned interface copy supports English and Simplified Chinese through native string catalogs; use SwiftUI localized literals and `String(localized:)` for dynamic presentation and errors. Keep identifiers, protocol values, and user content out of localization lookups. Meeting content and recognition fixtures may use supported languages. Run `python3 scripts/check_english.py` after copy or documentation changes; it also validates translation coverage and placeholders.

## Decision records

- Before finishing a task, update [`doc/DECISIONS.md`](doc/DECISIONS.md) if it establishes a lasting decision about product behavior, architecture, state machines, data models, security/privacy, dependencies, or engineering workflow. Evaluate and verify the decision before recording it; do not present unadopted ideas as settled facts.
- Do not log ordinary implementation details, mechanical renames, changes uniquely determined by requirements, or easily reversible local choices. Keep the decision log from becoming a changelog.
- Give each decision a stable ID, date, status, context, final decision, rejected alternatives, rationale/tradeoffs, impact, and relevant files. Put new records first. Preserve replaced decisions as `Superseded` with a link to the replacement; do not rewrite history to imply the decision never changed.
- `DECISIONS.md` explains why; domain references explain what the current system is and how it works. Update both in the same task when behavior changes, checking them against source and tests.
- Do not add empty records for formality when a task makes no decision at this level; the final report need not claim a decision-log update.

## Workflow

1. Use [`doc/README.md`](doc/README.md) to select relevant references, then trace the user path and complete data flow through callers, implementation, and downstream consumers. Do not guess from filenames or documentation alone.
2. Write down the state invariants and failure scenarios before making the smallest complete change. Fix root causes instead of hiding underlying errors in the UI.
3. Separate pure logic from platform I/O for deterministic tests; do not duplicate production logic in tests.
4. Add or update XCTest coverage in the existing `SameWaveTests` target when changing pure logic, especially `CaptionStore`, lifecycle, parsing, insight merging, or persistence mapping. Do not skip validation.
5. Regenerate with XcodeGen after project configuration changes and review generated plist/entitlement diffs. Do not commit `.build`, DerivedData, generated xcodeproj files, or local configuration.
6. When a defect reveals a recurring blind spot, capture the lesson in a test, script, executable check, or short rule here. More comments alone are insufficient.

## Validation gate

Run from the repository root after every source or project configuration change:

```sh
xcodegen generate
xcodebuild -project SameWave.xcodeproj \
  -scheme SameWave \
  -configuration Debug \
  -derivedDataPath .build \
  CODE_SIGNING_ALLOWED=NO \
  build
```

- If a test target exists, run the corresponding `xcodebuild test` and report the actual scheme, destination, and result. Compilation alone is not a passing test run.
- Add minimal manual smoke tests for affected paths: launch/permissions, system audio, microphone, English-to-Chinese, direct Chinese display, overlapping speakers, pause/resume/end, crash recovery, history/export, or AI failure handling. Do not mechanically run unrelated scenarios.
- Under the continuing authorization in [`MEMORY.md`](MEMORY.md), once development and validation pass, run `./build.sh` by default to replace and launch `~/Desktop/SameWave.app` using the existing signature, without asking again. Then check the installed signature and desktop process. Follow explicit exceptions in the current task. Do not change or assume the personal certificate in the script applies to another environment.
- If validation cannot run, state the missing environment capability, alternative checks completed, and remaining risk. Do not silently skip it.

## Definition of done

- The requirement works end to end; obsolete paths are removed; there is no unrelated refactoring.
- Golden invariants hold; new behavior has repeatable validation or clear manual steps.
- XcodeGen and the unsigned Debug build pass, along with relevant tests.
- The desktop app has been replaced and launched by default, with signature and process checks passing, subject to explicit task exceptions.
- Lasting decisions are recorded in `doc/DECISIONS.md`, with related domain references updated.
- Changes to visible behavior, permissions, configuration, core state machines, or architecture are reflected in README, relevant `doc/` references, requirements, or the reference routing here.
- Report what changed, what was validated, and remaining risks. Comments and TODOs are not substitutes for unfinished work.
