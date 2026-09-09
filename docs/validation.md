# Validation record

Validated on macOS 26.6.2 (Apple silicon), Swift 6.3.3, with Xcode Command Line Tools. The package targets macOS 14+. An older Mac/OS and Intel hardware were not available for live testing.

## Automated and packaging checks

- `swift build`: passed.
- `swift run WorkspaceChecks`: **10/10 passed**, including cross-assignment selection guards, assignment-switch resets, safe empty catalog, reference coverage, sample-document/transcription consistency, score consistency, distribution metrics, and histogram coverage/counts.
- `bash scripts/package-app.sh`: release build and local ad hoc signing passed.
- `codesign --verify --strict "build/Grading Workspace.app"`: passed.
- `plutil -lint "build/Grading Workspace.app/Contents/Info.plist"`: passed.
- `xcrun swift-format lint --strict --recursive Sources Tests Package.swift`: passed.
- Shell syntax and tracked/untracked text whitespace checks: passed.

Plain `swift test` was attempted. The local Command Line Tools did not discover the bundled Testing framework automatically. Adding its framework search path allowed compilation, but execution failed because the installed toolchain lacks `lib_TestingInterop.dylib`. The suite therefore uses a small standard-library/Foundation Swift executable, with throwing expectations and a nonzero failure exit. No testing framework or external dependency was added to the app.

## Native UI inspection

The packaged app was launched and inspected through native accessibility state and actual screenshots.

- Both assignment selections and multiple candidates: document, inspector context, scores, and sample OCR text agree.
- Rubric, References, and OCR tabs: reachable; reference/exemplar content and longer document/transcription content scroll.
- Changing the candidate or inspector tab resets its content scroll position.
- Every scope in both assignments was exercised: overall plus three parts each. Displayed means and population standard deviations match fixtures.
- Annotation, import, score/feedback editing, approval, reference import, recognition/correction, anonymity, and sign-in controls report disabled states.
- Account sheet clearly says authentication and authorization are not connected; Return dismisses it.
- Option–Command–I collapses and expands statistics.
- Accessibility labels expose selected candidates, tab states, sample totals, metric values, histogram ranges/counts, and planned controls.
- Light and dark appearances inspected. The paper remains white with explicit dark text.
- Dragging to the minimum window size preserved the layout, statistics, and scrollable panes. The minimum-window capture is 1120×752 including window chrome; the SwiftUI content minimum is 1120×720.
- Corrected the histogram axis word wrapping and confined the paper shadow to the paper surface.

Keyboard shortcut/dismissal and accessibility-tree checks are complete. A full VoiceOver walkthrough and system-wide full-keyboard-access audit were not performed.

## Self-contained app verification

Copied the final app to a fresh directory under `/private/tmp`, temporarily renamed both debug and release development resource bundles, and launched the copied app. It displayed the complete math sample, rubric, and statistics successfully. Both development bundles were restored afterward.

The packaged fixture loader requires the resource bundle inside the app and does not use SwiftPM's development fallback when running as an `.app`.

## Screenshots

All content is synthetic. Screenshots are actual app captures.

- [Math / dark](screenshots/math-dark.jpg)
- [Writing / OCR / light](screenshots/writing-ocr-light.jpg)
- [Answer-key references / light](screenshots/references-light.jpg)
- [Minimum window / dark](screenshots/minimum-window-dark.jpg)
- [Grader access layout](screenshots/grader-access.jpg)

## Scope and remaining work

The PDF reader, OCR engine, authentication/authorization approach, storage, charting library, and any grading services remain unselected. Documents and histogram bars are SwiftUI presentations only. Scores and statistics are precomputed sample data. There is no import, processing, persistence, annotation editing, identity redaction, approval, or export implementation.

No distribution signing, notarization, universal build, real student data, account integration, or external service calls were used. No commits or pushes were made. The user's pre-existing `.codex/config.toml` change is preserved.
