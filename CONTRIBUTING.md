# Contributing to ex_dbos

Thanks for contributing to `ex_dbos`.

## Ground Rules

- Keep changes focused and small.
- Include tests for behavior changes.
- Keep docs in sync with code changes.
- Run the local quality checks before opening a PR.

## Local Setup

1. Install Elixir `~> 1.19` and Erlang/OTP `28`.
2. Clone the repository and install dependencies:

```bash
mix deps.get
```

## Development Commands

- Apply project style:

```bash
mix style
```

- Run the main quality pipeline:

```bash
mix quality
```

- Run coverage report:

```bash
mix coverage
```

- Run docs consistency checks only:

```bash
mix docs.check
```

Integration tests are optional and require a running PostgreSQL instance:

```bash
EX_DBOS_RUN_INTEGRATION=1 EX_DBOS_TEST_DATABASE_URL=postgres://postgres:postgres@localhost:5432/ex_dbos_test mix test --include integration
```

## Pull Request Checklist

Before opening a PR, verify:

1. `mix quality` passes locally.
2. New or changed behavior has tests.
3. `README.md` and `docs/*.md` are updated when API or behavior changes.
4. Commit messages clearly describe intent.

## CI Behavior

The GitHub Actions workflow is optimized by change type:

- Code/config changes run full `mix quality`.
- Docs-only changes run `mix docs.check`.
- Unrelated changes skip heavy jobs.

This keeps PR feedback fast while preserving quality gates.

## Reporting Issues

When filing an issue, include:

- Elixir and OTP versions
- `ex_dbos` version/commit
- Reproduction steps
- Expected vs actual behavior
- Relevant logs/errors
