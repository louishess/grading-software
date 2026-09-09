# Approved local grading implementation

Implement the user-approved plan: full macOS 14+/iPadOS 17+ workflow, read-only iPhone with workspace import. PDFKit, Vision, PencilKit/UIKit and AppKit ink, GRDB 7.11.1, Swift Charts, native file APIs and optional LocalAuthentication. No generative AI, cloud sync, institution accounts, analytics or secure-redaction claims. Synthetic development/validation only.

## Team branches

PM foundation and integration changes use PRs to main. Team A Documents, B Grading and C Storage each use an isolated worktree and branch with a PR to main. PM reviews/builds before merging. Each Sol High may use one Luna Max child with disjoint UI files, no deeper delegation. PM performs each team branch’s commits, pushes and PR operations; subagents do not mutate Git. No force pushes, history rewrites or destructive cleanup. Existing root documentation changes are preserved.

## Shared contracts

`Domain/WorkspaceDomain.swift` is PM-owned. Snapshot WorkspaceData carries logical workspace id, local containerID and revision lineage. C persists snapshot revisions transactionally, originals as hashed separate files, identities separately from snapshot payload. PageRegion uses document revision, stable page ID and unrotated PDF point coordinates (lower-left), preserving crop/media origins/rotation. OCR uses ordered text and imageCrop blocks with original observations and separate corrections. PointValue stores Int64 hundredths; scores missing vs explicit zero, range validation, no intermediate rounding. WorkSubmission has reviewRevisionID, immutable review history and approvals tied to review+rubric revisions. Every substantive edit must invalidate approval; appearance/navigation do not.

## Order

1. PM platform/contracts and GRDB pin; C storage/recovery; A document geometry/reader; B rubric/scoring.
2. Import with preview/order/association, editable rubrics and references, manual scores.
3. Highlights/text notes/ink, undo/autosave, Vision OCR and teacher-assisted equation crops, optional app lock and display masks.
4. Draft-reviewed-approved history, approved/draft statistics, CSV/JSON and editable+flattened PDF exports, backup/manual transfer.
5. End-to-end synthetic validation, packaged Mac launch and Xcode iOS builds where available.

## Behavioral defaults

Encrypted/damaged PDFs rejected. Import PDF/JPEG/PNG/HEIC and preserve originals. English OCR plus supported-language selection; no guaranteed equation detector. Region candidates may come from Vision but teacher confirms and can draw/resize crops. OCR optional for grading. Points <=2 decimal digits, criterion maxima determine weights, totals derived; preserve prior scores as unconfirmed after evidence/rubric change. Feedback optional. Approved statistics by default; explicit separate complete draft/reviewed cohort, population SD, tied modes, ten bins including maximum.

Optional device-owner lock defaults off; supported password/passcode fallback; background or 5-minute inactivity relock; failures closed. Identity masking opt-in, not redaction. Full archives contain originals/identities and omit auth state. One .gradingworkspace SQLite archive with snapshot+manifest+hashed asset blobs. Duplicate logical id+head is idempotent; differing heads become separate local copies, never replacement/merge. Manual backups and pre-migration safety snapshots.

## Gates

Original hashes unchanged; staged-write fault recovery; exact score boundaries and approvals invalidated on any reviewed-evidence change; archive corruption/path/hash/revision checks; OCR cancellation/crop coordinate tests; annotation rotations/crop origins/zoom/reopen/export; CSV injection-safe text; stale-export rejection; offline runtime; light/dark, keyboard, VoiceOver and Pencil. Report missing physical-device/Intel/older OS checks honestly. Full Xcode is currently unavailable, so iOS device/simulator execution remains an environment prerequisite.
