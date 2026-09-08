# Repository Guidelines

## Project Structure & Module Organization

This repository is the starting point for a teacher-reviewed grading assistant. `README.md` describes the confirmed workflow and setup status; `docs/product-plan.md` records proposed milestones and open decisions. `.github/` contains the pull request template, and `.codex/config.toml` stores project agent settings. There is no application code, test suite, or asset directory yet. Introduce `src/`, `tests/`, and `assets/` as needed when selecting the stack.

## Build, Test, and Development Commands

No application build or development commands exist. Add exact install, run, build, and test commands to `README.md` with the first implementation.

- `git status --short` — inspect changed and untracked files.
- `git diff --check` — check unstaged tracked changes for whitespace errors.
- `git diff --cached --check` — check staged changes, including new files.

## Coding Style & Naming Conventions

Follow `.editorconfig`: UTF-8, LF endings, final newlines, spaces, two-space indentation by default, and four spaces for Python. Select a language-appropriate formatter and linter with the initial application code. Use descriptive domain names. Keep scoring rules separate from document parsing, model calls, storage, and UI code.

## Testing Guidelines

No framework or coverage threshold is configured. Add focused tests with the first implementation, covering rubric validation, score boundaries, rounding, approval transitions, failed imports, and exported values. Use synthetic fixtures and behavior-oriented test names. Add regression tests for calculation and data-loss defects.

## Commit & Pull Request Guidelines

Use short imperative subjects, such as `Add rubric validation`. Keep commits focused and use `codex/` for new feature branches. Follow `.github/pull_request_template.md`: explain behavior, link relevant issues, record validation, and attach screenshots for UI changes. Identify checks not run.

## Data & Review Boundaries

Never commit real student submissions, grades, or credentials. Use ignored local data directories. Treat suggested grades as drafts until teacher approval. Preserve original submissions and distinguish suggestions from teacher edits.

## Agent Instructions

The configured concurrency limit is six subagents, subject to the active runtime's cap. Limit delegation to depth two: the primary agent is depth zero, its children are depth one, and grandchildren are depth two. Depth-two agents must not spawn agents. Codex V2 ignores the legacy `max_depth` setting, so follow this instruction explicitly. Keep final integration, commits, and pushes with the primary agent.
