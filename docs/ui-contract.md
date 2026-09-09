# Frozen UI contract

Read AGENTS.md first. The user's latest instruction defers PDF reader and supporting software choices. This is SwiftUI presentation only; PDFKit, Charts, OCR, storage, authentication, third-party packages, actual PDFs, and service protocols are out of scope.

## Component signatures

All features are in the WorkspaceKit module; no imports of WorkspaceKit are needed inside it. Read Models/PreviewModels.swift and Shared/WorkspaceStyle.swift. Keep these exact entry points:

- `DocumentPane(assignment: AssignmentPreview, submission: SubmissionPreview?)`
- `ReviewPane(assignment: AssignmentPreview, submission: SubmissionPreview?, selectedTab: Binding<InspectorTab>)`
- `StatisticsPane(assignment: AssignmentPreview, selectedScopeID: Binding<String>)`

Do not edit these argument types, shared files, or other features. Read any shared file as needed. Feature-private helpers may be added only in your assigned directory. Local ephemeral presentation state is allowed, but assignment/submission/part selection remains in the supervisor's store.

## Appearance and geometry

Use WorkspaceStyle for adaptive colors and shared PreviewBadge, PlannedButton, workspaceCard() as appropriate. Warm neutrals, navy headings, teal accent, white/dark cards, system typography. Avoid excessive uppercase text, redundant cards, fixed document widths, or novelty decoration. Body text should be legible and all vertical content scrollable. Disabled controls need both a visible short explanation nearby and a help/accessibility label.

The window starts at 1360×900 and is at least 1120×720. Header 70; footer 26; sidebar 226; review inspector 330. Document occupies the remaining width (about 562 at minimum). Statistics header 40 and expanded pane 222 high span document and inspector widths, excluding the sidebar. Feature panes must cope with the remaining height; use ScrollView where appropriate.

## Document feature

Paper-like SwiftUI mock document based on submission.document: title, subtitle, sections with heading/prompt/response. Show candidate label and sample document status. This is not a PDF reader. Keep a visible “Document layout preview” label. Disabled highlight, note, draw, feedback controls; no zoom/reader functionality. Show an empty/unavailable state if submission is nil or sections are empty. No view that can edit sample content. Paper may stay white in dark mode like an actual page, with explicit dark text.

## Review feature

Segmented tabs Rubric, References, OCR driven by selectedTab binding. Rubric: sample total, criterion score/maximum, descriptions and performance guidance, read-only feedback. References: answer-key and exemplar cards, with part title associations. OCR: sample transcription clearly labeled as manually supplied preview text, no recognition performed. Disable score editing, feedback editing, reference import, recognition/correction, and approval with short visible explanations. Tab content must scroll in the 330-point inspector.

## Statistics feature

Top row scope picker (overall plus assignment parts using statistics IDs), n, sample label. Display mean, median, modes (none if empty), range, explicitly labeled population standard deviation, and min/max context. Use precomputed values; do not add a statistical engine. Static histogram of supplied bins via SwiftUI Shapes only, counts plus score-range labels and accessible descriptions. Label both axes. Display a useful empty state for missing scope or empty scores. Fit within 222 points height and width 892 or more; metrics left, histogram right is suggested. Every assignment part must be selectable.

## Validation ownership

Supervisor owns builds/tests to avoid concurrent SwiftPM contention. Agents should use `xcrun swift-format format --in-place --recursive <owned directory>` and lint their directory. Return changed paths and an honest validation report. Do not run builds unless asked; the supervisor will send any compile failures back.
