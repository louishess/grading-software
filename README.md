# Grading Workspace

A native SwiftUI macOS **visual skeleton** for a teacher-reviewed grading assistant.

This milestone establishes the layout and sample navigation. The PDF reader and supporting software will be selected later. The app does not import, edit, recognize, redact, authenticate, grade, save, approve, or export anything.

## Run locally

Requires macOS 14 or later and a Swift 6 toolchain (Xcode Command Line Tools are sufficient). There are no third-party dependencies or service accounts.

```sh
swift build
swift run GradingWorkspace
swift run WorkspaceChecks
swift build -c release
bash scripts/package-app.sh
open "build/Grading Workspace.app"
```

The script creates a locally launchable, ad hoc signed app containing its own sample resources. It is built for the current Mac's architecture. Developer ID distribution signing, notarization, and a universal binary are outside this milestone.

SwiftPM needs access to normal compiler caches and its manifest sandbox. If running inside a restricted agent environment, grant the build tool the necessary execution permission; no app dependencies need downloading.

## Explore the interface

- Select **Quadratic reasoning** or **The case for green spaces**, then choose a sample candidate.
- Read the paper-like document layout. It is a SwiftUI preview, not a PDF reader.
- Switch **Rubric**, **References**, and **OCR** to inspect sample scores, feedback, answer keys, exemplars, and manually supplied transcription text.
- Expand or collapse **Assignment insights** (Option–Command–I) and switch the whole-assignment/part selector.
- Use the appearance menu for system, light, or dark appearance.
- Open **Grader access** to inspect the planned account layout. No credentials are requested.

All other feature controls are disabled and labeled as planned. The app shows candidate identifiers from synthetic fixtures, not redacted identities. Every example is a sample draft; no grades have been approved.

Statistics are precomputed examples for six synthetic submissions per assignment. Each part has its own distribution. Standard deviation is the population standard deviation; range is maximum minus minimum; the mode display supports ties and no repeated values. Neither statistics nor example totals are calculated by a runtime grading engine.

## Development

The 10 focused checks use a dependency-free Swift executable. On this Mac, plain `swift test` could not run because the Command Line Tools Swift Testing installation lacks `lib_TestingInterop.dylib`. `swift run WorkspaceChecks` runs the same checks without that framework and exits nonzero on failure. The app does not depend on the check runner.

```sh
xcrun swift-format format --in-place --recursive Sources Tests Package.swift
xcrun swift-format lint --strict --recursive Sources Tests Package.swift
git diff --check
git diff --cached --check
```

Subagents must format only their assigned directory. The full formatting command above is for the supervisor or a developer owning the complete checkout.

- `Sources/GradingWorkspace/`: application entry point.
- `Sources/WorkspaceKit/Models/`: immutable display models, bundled fixture loader, and central selection store.
- `Sources/WorkspaceKit/Shell/` and `Shared/`: layout, appearance, and shared controls.
- `Sources/WorkspaceKit/Features/`: document, review, and statistics presentation.
- `Sources/WorkspaceKit/Resources/`: synthetic JSON, packaged with the app.
- `Tests/WorkspaceKitTests/`: selection and fixture consistency tests.
- `scripts/generate-fixtures.py`: optional Python 3 standard-library fixture authoring tool; not part of the app or its runtime.
- `docs/ui-contract.md`: bounded feature interfaces and ownership.
- `docs/product-plan.md`: delivered scope and deferred decisions.
- `docs/validation.md`: validation evidence and screenshot locations.

Regenerate synthetic fixtures only when intentionally updating the examples:

```sh
python3 scripts/generate-fixtures.py
swift run WorkspaceChecks
```

## Data and agent boundaries

Do not commit real student submissions, grades, or credentials. Local `data/`, `uploads/`, `exports/`, and `private/` directories are ignored. This app does not read them.

The active milestone permits at most three Luna Max subagents, each with an exclusive feature directory and no further delegation. The supervisor owns shared code, integration, and final validation. The existing user change to `.codex/config.toml` is preserved; the stricter milestone cap is enforced by `AGENTS.md` and dispatch.

Future suggestions must remain drafts until teacher approval. Original work, model suggestions, and teacher edits must remain distinguishable when those features are implemented.
