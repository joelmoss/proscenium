# Coding standards

Review rules for the judgement calls no linter makes. RuboCop, golangci-lint and jactionlint
cover the rest (see Linting in AGENTS.md).

## A rename, move or deletion reaches the whole repo

For every name the diff renames, moves or deletes (file, constant, method, fixture gem, guide),
`git grep` the old name across the whole repo and flag each hit the diff leaves behind. Past misses
lived outside `lib/` and `test/`:

- `Gemfile`, `gemfiles/*.gemfile` and `fixtures/adopted/Gemfile`, which name the fixture gems as
  `path:` gems, so a deleted fixture breaks `rake compile:local` and `bun test`
- the `paths:` filters in `.github/workflows/main.yml`, which name the guide files
- `docs/AUDIT.md` Progress rows, `TODOS.md`, README, AGENTS.md and code comments

## Public Ruby API is used outside this repo

A diff that removes, renames or privatises a public method or constant needs a sweep of the
consumer apps and sibling gems, not an in-repo grep: the 2026-10-10 audit called two methods dead
that consumers call. The sweep and the repo list are in the user's memory
(`consumer-usage-check`); if it is not loaded, ask. Report hits with the placeholder names in
AGENTS.md, never the real ones.
