# Functional implementation validation

This file records the functional milestone separately from the preserved presentation-only validation and handoff documents. All development inputs are synthetic.

## Environment

- Local target: macOS 14+; installed Command Line Tools Swift 6.3.3.
- The local machine currently has no full Xcode installation selected. Local iOS simulator/device execution is therefore unavailable.
- The Xcode project targets Mac and iOS/iPadOS 17+, with iPhone limited to import and review. CI includes a generic iOS Simulator build.
- Dependency: GRDB pinned to 7.11.1 in the Swift package resolution.

## Review structure

Each Sol team uses an isolated `codex/` branch and worktree. The PM owns Git staging, commits, pushes, PR creation, review comments, and merges. Luna children do not mutate Git. Shared shell/platform changes use the integration branch.

GitHub prevents an author account from formally approving its own PR. PM review decisions are recorded in PR comments and exact-head merges after the applicable checks.

## Automated checks

The integrated Mac build passed. FunctionalChecks passed all five suites, including a repeat with process network access denied by sandbox-exec. Strict repository-wide Swift formatting and whitespace checks passed. Existing fixture checks passed 10/10 in each team branch. The expected CoreGraphics warning comes from deliberately damaged synthetic PDF input.

Reopening was compared with exact equality for grading and evidence data, allowing less than one microsecond for Date epoch conversion in JSON. No score, source hash, mark, crop, identity, approval, or history identifier difference was accepted.

The suites exercise:

- Storage: revision conflicts, original byte hashes, staged-write crash points, archive identity and asset integrity, current and historical asset transfer, duplicate/divergent copies, interrupted restore, failed export publication, and device-local lock state.
- Grading: exact point parsing, missing versus zero, scoring bounds, review/approval invalidation, rubric import validation, statistics populations/bins, export eligibility/provenance, and CSV escaping.
- Documents: geometry across page rotations and crop origins, PDF and image inspection/rendering, text OCR and cancellation, teacher correction preservation, editable/flattened export semantics, original and hard-link protection.
- Images: PNG/JPEG/HEIC inspection and pixel checks, EXIF orientation 6, source crop alignment, malformed/truncated input rejection, cancellation, and unchanged source bytes. HEIC encoding was available and ran on this Mac.
- Integrated workflow: import synthetic PDF → annotate/equation crop → score → review → approve → CSV/JSON/PDF export → reopen → transfer → invalidate → reject stale save/export → retain a divergent copy.

## Acceptance not established by compilation

Physical Pencil interaction, Touch ID/Face ID/system fallback prompts, real Mac–iPad–Mac continuation, iPhone/iPad touch usability, VoiceOver usability, older supported operating systems, and Intel hardware require device checks. Automated tests use injected authentication and local directories to simulate device transfer; those are not physical-device results.

The local Mac package is ad hoc signed for the build machine's architecture. Notarization, public distribution, App Store/TestFlight, and paid enrollment are outside this implementation.

## Isolated pull requests

- Foundation: [PR #1](https://github.com/louishess/grading-software/pull/1), merged after baseline checks.
- Storage: [PR #2](https://github.com/louishess/grading-software/pull/2), merged after its focused suite.
- Grading: [PR #3](https://github.com/louishess/grading-software/pull/3), merged after its focused suite.
- Cross-connection stale-save correction: [PR #4](https://github.com/louishess/grading-software/pull/4), merged after a simultaneous-save regression.
- Documents: [PR #5](https://github.com/louishess/grading-software/pull/5), merged after native reader, crop, correction and PDF acceptance.

- Accessibility masking: [PR #7](https://github.com/louishess/grading-software/pull/7), merged after the packaged PDF accessibility subtree was verified hidden under masking.
- Archive timestamp precision: [PR #8](https://github.com/louishess/grading-software/pull/8), merged after a deterministic nonzero codec-delta regression and integrated/offline checks.
- Platform and shell integration: [PR #6](https://github.com/louishess/grading-software/pull/6), gated by final Mac tests and iOS Simulator compilation.

## Packaged Mac acceptance

The ad hoc signed Mac app was launched independently with a dedicated synthetic workspace root. Live checks confirmed:

- Persisted highlights and notes appear in Select mode after reopening.
- A dragged equation crop displays the source equation, accepts a revised width, and saves an explicit teacher correction.
- The evidence change returns Approved work to Draft, retains the score as unconfirmed, and permits reconfirmation → Reviewed → Approved with history preserved.
- Native export preflight and destination selection save CSV, JSON, editable PDF and flattened PDF together. Saved CSV contains the exact 8.75 score and omits the optional student name.
- A full workspace archive saves through its native destination dialog.
- Document import presents candidate association and ordering; importing the same source again is recognized without changing the approved revision.
- Import from inside the rubric editor waits until the editor is dismissed; cancelling the native picker returns without a false failure alert.
- A zero-border-width display mask saves, remains opaque after reopening, leaves approval current, and hides the native PDF accessibility subtree when masking is enabled. The original document remains unchanged.
- Light and dark presentation and accessible control labels were inspected. The statistics view shows the current approved population.

The live inspection caught and corrected overlay installation order, competing native file dialogs, crop/correction editing gaps, a zero-width display-mask validation mismatch, and unnecessary reader replacement during ordinary saves. Interface screenshots were inspected in the task; no claim is made that a complete VoiceOver session or every minimum-size layout was exercised.

Native editable/flattened export images were visually inspected. The original equation, highlight and teacher note were present, and the editable/flattened annotation counts were checked programmatically. Display masks are excluded from PDF exports.

## Continuous integration

[The integration build](https://github.com/louishess/grading-software/actions/runs/34304969792) passed Mac compilation/tests and a generic iOS Simulator build. This confirms iOS compilation, not simulator interaction or physical-device acceptance. The final head status is recorded in [PR #6 checks](https://github.com/louishess/grading-software/pull/6/checks); a passing Mac/test/iOS Simulator job is required before integration merges.


## Timestamp precision regression

Final acceptance reproduced an intermittent false archive rejection from comparing decoded JSON milliseconds with SQLite seconds using exact Date equality. Archive timestamp comparisons now require an absolute difference strictly below one microsecond. A deterministic fixture asserts a nonzero codec round-trip delta and verifies both acceptance and rejection boundaries. Revision IDs, parents, hashes, scores and all evidence remain exact. The full five suites passed again after this fix, including a repeat with network access denied.

The CI test also exercises inactivity relocking with a bounded wait for the observable locked state. A fixed 60 ms test sleep was unreliable on the shared CI executor; the production five-minute inactivity duration was not changed.
