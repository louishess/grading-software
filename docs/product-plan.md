# Product plan

## Current milestone: presentation-only macOS skeleton

Swift 6 and SwiftUI, macOS 14+, two bundled synthetic assignments, one document-focused workspace. A custom warm-neutral/navy/teal design supports light and dark appearance. Working behaviors are limited to sample assignment/submission selection, inspector navigation, statistics scope selection, pane expansion, and appearance changes.

The latest user instruction explicitly defers the choice of PDF reader and all supporting software. Document pages and histogram bars are SwiftUI presentation. No PDFKit, Swift Charts, OCR engine, storage system, authentication provider, or third-party package is integrated or selected.

The visual destinations are:

1. Assignment/submission sidebar and sample review progress.
2. Paper-like submitted-work preview and planned annotation/feedback tools.
3. Rubric with criterion descriptions, sample scores, and feedback.
4. Answer-key and exemplar references, associated with assignment parts.
5. Manually supplied OCR transcription preview.
6. Whole-assignment and per-part sample statistics: mean, median, mode, range, population standard deviation, and distribution.
7. Planned anonymity mode and grader-access layout.

Disabled controls must not claim processing or success. Sample IDs are not automatic redaction. Sample account screens do not secure access. No data is persisted, approved, exported, or transmitted.

## Skeleton acceptance

- Build and package a locally launchable app with no third-party dependencies.
- Select both synthetic assignments, their candidates, inspector tabs, and all statistics scopes.
- Keep document, rubric, feedback, transcription, and selected candidate consistent.
- Verify supplied sample scores, totals, metrics, and histogram counts agree through fixture tests.
- Show every future feature clearly with disabled controls and short explanations.
- Inspect light/dark appearance, minimum window layout, scrolling, and keyboard/accessibility affordances.
- Verify the packaged app loads bundled resources independently of the source checkout.
- Record evidence and unperformed checks in `validation.md`.

## Next decisions — no implementation authorization yet

- Compare PDF reader/editor options for annotations, feedback, document fidelity, licensing, and macOS integration.
- Evaluate handwriting/OCR software with representative synthetic samples.
- Define rubric import formats, reference-answer handling, partial-credit rules, and rounding.
- Determine how grader identity and assignment authorization will be verified.
- Design identity detection and redaction, including information embedded in document content and metadata.
- Select storage, backups, retention, deletion behavior, and permitted external processing.
- Decide whether any automated grading provider is appropriate and define operating cost and review controls.
- Define statistics inclusion rules for missing, incomplete, draft, and approved results.
- Select export formats and destinations.

## Later workflow requirements

Import assignment materials, submissions, and rubric; review their accuracy; inspect any suggested scores and feedback; edit and explicitly approve as the teacher; export only approved results.

Missing/unreadable work remains unresolved rather than receiving an automatic zero. Edits to submissions, rubric, or grades invalidate previous approval. Preserve original work and distinguish suggested content from teacher edits.

Later tests must cover scoring boundaries, rounding, failed imports/model calls, approval transitions, recoverability, and exported values. None of those workflows is claimed by the visual skeleton. School-system synchronization, automatic grade publication, institutional account administration, and collaboration remain deferred.
