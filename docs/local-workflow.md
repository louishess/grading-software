# Local grading workflow

This implementation uses free native Apple frameworks and GRDB 7.11.1. Primary processing and storage stay on the device. The earlier presentation handoff, README, and product-plan edits are preserved as historical material; the approved functional scope is in [implementation-plan.md](implementation-plan.md).

## Build and run

Use macOS 14 or later and Swift 6.1 or later. Full Xcode is required for iOS simulator/device builds.

```sh
swift build
swift run WorkspaceChecks
swift run FunctionalChecks
bash scripts/package-app.sh
open "build/Grading Workspace.app"
```

The Mac packaging script creates an ad hoc signed app for the current Mac architecture, including its Swift package resource bundles. It does not create a universal, notarized, or App Store build.

Open `GradingWorkspace.xcodeproj`, choose the `GradingWorkspace` scheme, and choose a Mac, iPad simulator, iPhone simulator, or development device. A personal development signing team may be needed for a physical device. Simulator compilation can use:

```sh
xcodebuild -project GradingWorkspace.xcodeproj -scheme GradingWorkspace \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build/ios CODE_SIGNING_ALLOWED=NO build
```

SwiftPM downloads the pinned GRDB source for development. No service account or network connection is required by the running grading workflow.

## Create and grade work

1. Create a local workspace, then add an assignment and candidates. Candidate names are optional; each candidate also has a stable alias and identifier.
2. Edit the rubric: add ordered parts and criteria, maximum points, and reference text. A JSON rubric can be previewed and validated before applying it. A criterion's maximum determines its weight; totals are derived.
3. Select the candidate and import PDF, JPEG, PNG, or HEIC files. Review the association and file order. Originals are copied, hashed, and retained independently of marks or OCR. Encrypted PDFs are rejected in this version.
4. Read the document, add highlights, notes, or ink, and optionally run on-device text recognition. Select the recognition language from Vision's supported languages. OCR is optional for grading.
5. Use equation image crops where transcription is unsuitable. Use the Crop tool to draw a region, or choose Use source image on any OCR text block. Crop bounds can be resized/repositioned, and blocks can be reordered or removed. Save text corrections explicitly. Crops remain linked to the source page region; OCR does not claim to detect equations automatically. Teacher text corrections remain separate from original observations.
6. Enter criterion scores with up to two decimal places and optional written feedback. Blank means missing; type `0` for an explicit zero. Values are stored as integer hundredths of a point.
7. Mark complete work Reviewed, then explicitly Approve it. Substantive rubric, reference, source-evidence, score, or feedback edits return affected work to Draft. Matching prior scores remain visible but need confirmation. Display preferences and display masks do not approve or change grading evidence.
8. Open statistics to compare current approved results, or the separately labeled complete draft/reviewed cohort. Missing work is excluded and counts are displayed. Standard deviation uses the population convention.
9. Export current approved work as CSV, JSON, editable annotated PDF, or a separate flattened PDF. The preflight shows included/excluded work and optional identity fields. Structured exports default to candidate IDs. Original PDF pages can still identify a student.

## Back up and transfer

A `.gradingworkspace` file is a versioned SQLite archive containing workspace snapshots, revision history, original and derived assets, and identity mappings. It is a full backup, including drafts. It is not an anonymous export.

Choose an archive through the operating system's file interface on the other device. A matching workspace/revision is recognized as a duplicate. A different revision is retained as a separate local copy. Import never automatically replaces or merges the current workspace. Choose the copy to open explicitly.

The iPhone interface imports workspace copies and supports read-only document and grading review. Editing is intended for Mac and iPad.

## Local access and identity display

The optional device-owner lock starts disabled. When enabled, the app uses LocalAuthentication and supported system password/passcode fallback, and relocks after backgrounding or five minutes without activity. Lock preferences stay on the device and are excluded from transfer archives. This is not institutional authorization or database encryption.

Identity masking uses aliases in supported labels and accessibility descriptions. Manually selected display masks conceal regions in the reader. These are reversible viewing controls, not secure redaction. Originals, handwriting, file metadata, and identifying text remain in workspace archives and may appear in PDF exports.

## Storage and recovery

Default local storage is the application's Application Support `GradingWorkspace` directory. Original assets are app-owned immutable files referenced by SHA-256. SQLite transactions use expected-revision checks; the UI reports stale edits instead of overwriting a newer save.

Staged filesystem writes and operation journals allow interrupted imports to recover. Incomplete bytes are kept out of active submission records. Failed output preparation is not reported as an export success. Workspaces are validated before use; damaged inputs do not produce empty successful submissions.

For synthetic development, `GRADING_WORKSPACE_ROOT` selects a separate local root. `GRADING_ACCEPTANCE_OUTPUT` retains synthetic end-to-end test workspaces and export artifacts. Never point either at student data during automated development checks.

## Delivery limits

See [implementation-validation.md](implementation-validation.md) for actual checks and unperformed acceptance. Compilation does not establish Pencil behavior, biometric prompts, physical-device transfer, VoiceOver usability, Intel behavior, or older-OS compatibility. Public distribution, automatic synchronization, institutional accounts, AI grading, mathematical transcription, and irreversible redaction are outside this scope.
