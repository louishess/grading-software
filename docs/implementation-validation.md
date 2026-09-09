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
- Documents: [PR #5](https://github.com/louishess/grading-software/pull/5), final integration review in progress.

Packaged UI, export image review, and CI results are recorded below as they complete.
