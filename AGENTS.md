# Repository Guidelines

## Active milestone: presentation-only SwiftUI skeleton

Build only the approved appearance and sample navigation. The PDF reader and all other supporting software will be selected in a later milestone.

- Use synthetic bundled fixtures exclusively. Do not read student directories, request credentials, make network calls, or add analytics.
- Allowed behavior: sample assignment/submission selection, inspector tabs, panel expansion, appearance selection, and switching precomputed statistics.
- Render paper-like document previews and static histogram bars with SwiftUI. Do not integrate PDFKit, Swift Charts, WebKit, OCR, authentication, storage, or third-party packages. Do not create PDFs.
- Do not implement document import/editing, annotations, persistence, rubric scoring/calculation, automatic grading, redaction, authorization, exports, or grade approval.
- Unimplemented actions must be visibly disabled with a short explanation. Never show fabricated processing, saving, authentication, or redaction success.
- Keep immutable presentation models separate from views. Do not add speculative service layers, protocols, dependencies, or framework selections.
- Each subagent may edit only paths named in its assignment. Shared interfaces, fixtures, styling, app entry points, package files, scripts, documentation, and agent configuration belong to the supervisor.
- Report needed changes outside your ownership to the supervisor; continue independent work within your assigned boundary.
- Use `gpt-5.6-luna` with `max` reasoning for assigned UI work. Maximum concurrent subagents: three, subject to the runtime cap.
- Subagents must not spawn agents or delegate further.
- Subagents must not stage, commit, push, switch branches, reset, clean, or otherwise mutate Git state.
- Do not overwrite another agent's work or unrelated user changes.
- Completion reports must identify changed files, validation performed, limitations, and shared-interface requests. Distinguish navigation from placeholders.
- The supervisor owns integration, final validation, and any separately authorized commits or pushes.

## Project structure and commands

`Sources/GradingWorkspace` is the app entry point. `Sources/WorkspaceKit` contains the shell, immutable presentation models, synthetic resources, and feature directories. `Tests/WorkspaceKitTests` tests sample selection and fixture integrity. `scripts/` holds local packaging utilities. `docs/product-plan.md` distinguishes this milestone from future work.

- `swift build` — build.
- `swift run GradingWorkspace` — run from source.
- `swift run WorkspaceChecks` — focused tests.
- `swift build -c release` — optimized executable.
- `bash scripts/package-app.sh` — local app at `build/Grading Workspace.app`.
- `xcrun swift-format lint --strict --recursive Sources Tests Package.swift` — Swift format/lint check.
- `git diff --check` and `git diff --cached --check` — whitespace checks.

Use Swift 6 and macOS 14+, descriptive domain names, and two-space Swift indentation. Follow `.editorconfig`; use the toolchain's `swift-format`. Only format files you own.

## Validation and data boundaries

Test assignment selection, valid part selection, reference/resource integrity, and consistency of precomputed fixture statistics. There is no grading engine or PDF reader to test. Future work must cover scoring boundaries, rounding, approval transitions, failed imports, and exported values before claiming those features work.

Launch the packaged app; inspect both assignments, every panel, light/dark appearance, minimum window layout, keyboard navigation, and accessibility labels. Report unperformed checks honestly. Keep screenshots synthetic.

Never commit real student submissions, grades, or credentials. Keep local data in ignored directories. Future suggested grades remain drafts until teacher approval; preserve originals and distinguish suggestions from teacher edits.

## Git and review

Use short imperative commit subjects and `codex/` for new feature branches. Follow `.github/pull_request_template.md`, including validation and UI screenshots. Do not commit or push unless separately authorized. Preserve the existing user modification to `.codex/config.toml`; enforce this milestone's stricter delegation cap here and at dispatch.
