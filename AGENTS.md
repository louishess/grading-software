# Repository Guidelines

## Active milestone: local Mac/iPad grading workspace

The user approved the functional implementation plan in docs/implementation-plan.md. Build a fully local manual grading workflow on macOS 14+ and iPadOS 17+, with workspace import and read-only review on iPhone.

- Approved: PDFKit, Vision, PencilKit on iPad, AppKit ink on Mac, GRDB/SQLite, Swift Charts, native file APIs and LocalAuthentication.
- Preserve original documents. Store revisions, annotations, OCR observations/corrections, equation crops, scores and approvals separately. Missing scores are not zero. No generative AI, institutional authentication, automatic synchronization, analytics, or irreversible redaction.
- Runtime processing stays local. Development dependency downloads and official documentation research are allowed. Use synthetic data exclusively for development/validation; never inspect student folders or request credentials.
- Never claim a failed save/import/export succeeded. Clearly label display masking as distinct from secure redaction.
- Keep presentation and domain models separate. Shared models/interfaces, fixtures, styling, shell, app targets, package/project files, scripts, documentation and agent configuration belong to the PM.

## Multiagent ownership

- PM may dispatch up to THREE gpt-5.6-sol agents at high effort. Each may dispatch at most ONE gpt-5.6-luna child at max effort, with no deeper delegation. Six subagents maximum, subject to runtime capacity. Use fewer when sufficient.
- Explicit model/effort dispatches use fork_turns none with complete task context.
- Each agent edits only its assigned file allowlist. Parent and child have disjoint writes. Request PM changes to shared files rather than editing them.
- Each Sol team works in its own PM-created worktree/branch. PM stages and commits only that team's assigned files, pushes without force, and opens its PR to main. Subagents do not mutate Git. PM reviews and merges validated PRs without rewriting history, resetting, cleaning, or altering unrelated work.
- PM runs integrated builds/tests; agents may author focused tests and format only owned files.
- Report changed paths, validation, limitations and shared-interface requests. Preserve unrelated user changes.
- Preserve .codex/config.toml concurrency 8 and legacy depth 2. Enforce the approved narrower structure through dispatch.

## Development and validation

Swift 6.1+, macOS 14+, iOS/iPadOS 17+, two-space indentation and swift-format. Commands: swift build; swift run WorkspaceChecks; swift run FunctionalChecks; swift build -c release; bash scripts/package-app.sh; xcrun swift-format lint --strict --recursive Sources Tests Package.swift; git diff --check.

Full Xcode is required for iOS simulator/device validation. Do not equate compilation with physical Pencil, biometric, VoiceOver, Intel, or older-OS acceptance. Report unavailable checks.

Test staged-write recovery, original hashes, exact hundredths-point calculations, revision invalidation, archive integrity/conflicts, mixed OCR crops, annotation coordinates and editable/flattened PDF export. Use only synthetic fixtures.

The user authorized team branches, commits, pushes and PRs to main for this implementation; PM reviews and merges. Use codex/ for any new branch. Follow .github/pull_request_template.md for separately requested PRs.
