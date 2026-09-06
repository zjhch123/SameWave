# SameWave Project Memory

## UI design direction

- Use a native Apple/macOS visual style throughout the app, following Apple Human Interface Guidelines.
- On 2026-09-05, the user authorized using OpenDesign MCP as the UI/UX designer. Commission relevant design work there and implement the reviewed result in native SwiftUI.

## Automatically install and launch after development

- On 2026-09-05, the user explicitly requested that every completed development task replace and launch the desktop app without asking again.
- First complete the build and tests required by `AGENTS.md`, then run `./build.sh` from the repository root, using the existing signing configuration to replace and launch `~/Desktop/SameWave.app`.
- After installation, verify the app signature and desktop process. Confirm successful launch before reporting completion.
- This is continuing authorization for this project. Follow any explicit instruction in the current task not to install or launch.
