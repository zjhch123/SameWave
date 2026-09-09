# SameWave Documentation

This directory is the repository's technical documentation hub, covering product boundaries, runtime behavior, long-term decisions, and validation. Domain references describe the current implementation; requirements describe intended behavior. Resolve conflicts against current source, [`project.yml`](../project.yml), and explicit requirements.

## At a glance

SameWave is a native macOS app for one-on-one meetings. It treats system audio as the other participant and the microphone as you, recognizes both locally, and translates or directly displays speech according to the selected English/Simplified Chinese source and target languages. Turns become ordered Sections, sessions save incrementally to SwiftData, and optional user-configured strict JSON Schema Structured Outputs services generate insights and refined transcripts. The interface supports English and Simplified Chinese through native localization. New AI insights follow the active interface language; saved results retain their original text. Generated meeting titles, prompt source text, export templates, and documentation remain in English; meeting content retains its selected languages.

## Read by task

| Question | Reference |
|---|---|
| Product scope, stack, layers, UI | [Product and architecture](01-product-and-architecture.md) |
| Audio, ASR, Section state machine, translation scheduling | [Live captions and translation](02-live-captions-and-translation.md) |
| Start, pause, resume, persistence, history, export | [Session lifecycle and data](03-session-lifecycle-and-data.md) |
| AI providers, insights, refinement, privacy | [AI insights and refinement](04-ai-insights-and-refinement.md) |
| Principles, evolution, boundaries, future decision order | [Design, evolution, and boundaries](05-design-evolution-and-boundaries.md) |
| Environment, build, permissions, change entry points, validation | [Development and validation](06-development-and-validation.md) |
| Accepted long-term decisions and rationale | [DECISIONS.md](DECISIONS.md) |
| September 9 history loss: evidence, reproduction, and prevention | [History storage incident](history-storage-incident-2026-09-09.md) |
| Conversation segmentation and rendering baseline | [Conversation rendering requirements](conversation-rendering-requirements.md) |
| Phase 2 validation and remaining smoke checks | [Phase 2 validation](phase-2-validation.md) |
| Phase 2 core requirements, adopted choices, and candidate extensions | [Phase 2 spec](phase-2-spec.md) (P2-R01–P2-R09 implemented; candidate extensions deferred) |

## Repository paths

```text
.
├── Sources/
│   ├── App/          # App assembly, window shell, settings navigation
│   ├── AI/           # Shared AI configuration, providers, response parsing
│   ├── Capture/      # Audio capture and recognition I/O
│   ├── Meeting/      # Live sessions, captions, translation
│   ├── History/      # Persistence, history UI, export
│   ├── Insights/     # AI insights, refinement, titles, vocabulary generation
│   ├── Shared/       # Cross-domain utilities
│   └── Resources/    # App resources and build metadata
├── Tests/            # Domain state, scheduling, persistence, AI parsing tests
├── doc/              # This documentation set
├── README.md         # Entry point for users and contributors
├── AGENTS.md         # Collaboration and validation rules
├── project.yml       # XcodeGen source of truth
└── build.sh          # Local signed installation script
```

- Use complete domain paths from the repository root, such as `Sources/Meeting/CaptionStore.swift` or `doc/02-live-captions-and-translation.md`.
- Link to source from this directory with `../Sources/...`.
- Generated `SameWave.xcodeproj` and build artifacts are not sources of documentation truth; [`project.yml`](../project.yml) owns project configuration.
- Documentation must not depend on external reference projects, experimental directories, or a specific parent directory name.

## Document types

- **Current implementation:** `01`–`06` describe behavior verifiable in current source.
- **Design baseline:** requirements may lead implementation; relevant references must disclose known differences.
- **Requirement specs:** [Phase 2](phase-2-spec.md) defines the accepted V2 release contract, preserving requirement and choice IDs for traceability. Candidate extensions remain deferred.
- **Decision records:** `DECISIONS.md` explains why decisions were made, rather than replacing domain documentation or a changelog.
