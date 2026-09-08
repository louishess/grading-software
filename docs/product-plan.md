# Product Plan

## Confirmed direction

Build a grading assistant for a teacher to upload assignments and a rubric, review suggested grades, and export results. The teacher controls final scores and feedback.

## Proposed first version

Start with one assignment and one rubric per grading batch. Keep the original submission available during review. Show the reason for each suggested criterion score and let the teacher edit it before approving the submission.

Use explicit states: imported, ready for suggestions, awaiting review, approved, and exported. Missing or unreadable work should remain visibly unresolved; do not assign a zero merely because extraction failed. Export only approved submissions and identify any excluded submissions.

## Milestones

1. **Runnable foundation:** choose the application platform, add local setup commands, and configure formatting, tests, and CI.
2. **Import and rubric review:** support an agreed initial file format, validate files, preserve originals, and let the teacher correct extracted text and rubric criteria.
3. **Suggested grading:** integrate an explicitly selected provider, produce criterion-level draft scores and feedback, and handle failures without losing work.
4. **Teacher review:** support edits and explicit approval; changes to the submission, rubric, or grade invalidate prior approval.
5. **Export:** generate an agreed format, preserve approved values, and validate the result against synthetic fixtures.

## Decisions to resolve before implementation

- Desktop application or locally hosted browser interface.
- Assignment types and initial formats: typed text, PDFs, scanned handwriting, or other documents.
- Rubric format and whether an answer key is also required.
- Model provider, processing location, and acceptable operating cost.
- Local storage, backups, retention, and deletion behavior.
- Required export columns, file format, and destination system.

These are open decisions, not implemented features.

## Acceptance criteria

- The teacher can complete one synthetic grading batch from import to export.
- Original work, rubric criteria, suggested scores, and teacher edits remain distinguishable.
- Totals and rounding match documented grading rules.
- Invalid files, failed extraction, and failed model calls are recoverable.
- Unapproved grades cannot be included in the approved-results export.
- Student work and credentials never enter source control or routine diagnostic logs.

## Initial exclusions

School-system synchronization, automatic grade publication, institutional account management, and multi-teacher collaboration are outside the proposed first version.
