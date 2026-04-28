# Audio Input Constitution

## Core Principles

### I. Code Quality
Every module must be self-contained, readable, and maintainable. Favor clarity over cleverness; prefer explicit code over implicit magic. Functions do one thing, have descriptive names, and stay under 40 lines. No dead code, no unused dependencies, no commented-out blocks. Consistent formatting is enforced by linters and formatters — zero warnings is the baseline. Dependencies are pinned; no floating ranges in production. Code reviews verify correctness, readability, and adherence to project conventions before merge.

### II. Test-First Development (NON-NEGOTIABLE)
Tests are written before implementation. Red-Green-Refactor cycle strictly enforced: write a failing test, get it to pass, then refactor. Every new feature, bug fix, or behavior change requires a corresponding test. Unit tests cover business logic and edge cases; integration tests cover cross-module contracts and data flows. Test coverage floor is 80% for all new code. Flaky tests are treated as P0 bugs — they are fixed or quarantined immediately, never ignored.

### III. User Experience Consistency
All user-facing interfaces follow a unified design system: consistent terminology, visual patterns, interaction models, and feedback mechanisms. Error messages are actionable — they tell the user what went wrong and how to fix it. Loading states, empty states, and failure states are first-class design concerns, never afterthoughts. Accessibility is not optional: keyboard navigation, screen reader support, and WCAG 2.1 AA compliance are required. Changes to UX patterns must be documented and applied project-wide, not piecemeal.

### IV. Performance Requirements
Every feature ships with defined performance budgets. API response times must stay under 200ms for p95 at the 95th percentile. Frontend interactions must respond within 100ms; time-to-interactive must stay under 3 seconds on target devices. Memory leaks are blockers, not nice-to-fixes. Audio processing pipelines must maintain real-time constraints — no buffer underruns or perceptible latency. Performance regressions are caught in CI; any regression beyond 10% on a benchmark blocks the merge.

### V. Simplicity
Start with the simplest solution that meets requirements. YAGNI: don't build abstractions for hypothetical future needs. Three similar lines are better than a premature abstraction. No half-finished implementations — either ship the feature complete or don't ship it. Prefer composition over inheritance, explicit over implicit, and flat over nested. When complexity is unavoidable, document the why, not the what.

## Security & Reliability

- Input validation at every system boundary — never trust external data.
- Secrets are never committed, logged, or exposed in error messages.
- Audio data is treated as untrusted input; sanitize before processing or storage.
- Graceful degradation over hard failure: when a component fails, the system degrades to a safe state rather than crashing.
- All external API calls have timeouts, retries with backoff, and circuit breakers.

## Development Workflow

- Feature branches follow the naming convention: `feature/<number>-<short-description>`.
- Commits are atomic and describe intent, not mechanics.
- PRs require passing CI, code review approval, and constitution compliance check.
- Breaking changes require a migration plan documented in the PR.
- No merge commits on feature branches — use rebase to maintain linear history.

## Governance

This constitution supersedes all other practices and conventions. Amendments require: (1) a written proposal with rationale, (2) team review and approval, (3) a migration plan for any existing code that violates the new principle. All PRs and code reviews must verify compliance. Complexity that contradicts these principles must be justified and documented.

**Version**: 1.0.0 | **Ratified**: 2026-04-23 | **Last Amended**: 2026-04-23
