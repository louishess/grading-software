# Grading Software

A personal grading assistant for processing assignments with a rubric, reviewing suggested grades, and exporting approved results.

## Status

Repository initialized. Application implementation has not started; there is no runnable app, model integration, or automated grading yet.

## First workflow

1. Upload an assignment, student submissions, and a grading rubric.
2. Review the imported material and rubric before generating suggestions.
3. Inspect suggested scores and feedback alongside the submitted work.
4. Edit and approve grades as the teacher.
5. Export approved results for use outside the application.

Suggestions remain drafts until reviewed. The first version will not automatically publish grades to students or a school system.

## Repository contents

- `AGENTS.md` — contributor and agent instructions.
- `docs/product-plan.md` — scope, proposed milestones, and decisions to resolve.
- `.codex/config.toml` — project-specific Codex subagent settings.
- `.github/pull_request_template.md` — change and validation checklist.

## Development

No language, dependencies, build system, or test framework has been selected. Add exact setup, run, and test commands here with the first implementation. Keep grading rules separate from document handling, model calls, storage, and the interface.

Before committing, inspect `git status --short` and run `git diff --cached --check` after staging. See [Repository Guidelines](AGENTS.md) for contribution conventions.

## Data handling

The repository is intended to be public. Commit synthetic examples only. Local `data/`, `uploads/`, `exports/`, and `private/` directories are ignored, as are environment files and common credential formats. Ignore rules do not replace reviewing staged files.

Choose and document storage, retention, and any external model service before processing real student work. Public source code does not imply public assignment data.

## Codex project settings

The project configuration sets `agents.max_concurrent_threads_per_session = 6` and `agents.max_depth = 2`. Current Codex V2 accepts but ignores the legacy depth setting, so `AGENTS.md` also directs agents to stop delegation at depth two. A running session can retain its existing concurrency cap; use a new session to load changed settings.

See the [official subagent configuration reference](https://learn.chatgpt.com/docs/agent-configuration/subagents).
