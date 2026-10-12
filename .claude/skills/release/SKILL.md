---
name: release
description: Cut a Proscenium release - bump the version, tag it, run release.yml to its approval gate, and write and publish the GitHub release notes. Use when asked to "release", "cut a release", "prepare a new release" or "publish x.y.z".
---

# Release Proscenium

Releases run from `.github/workflows/release.yml`, never from a laptop: `rake release` aborts on
purpose. AGENTS.md's "Releasing" section is the reference; this skill is the order to do it in.

## Usage

- `/release` - pick the version from the commits since the last tag
- `/release 0.27.0` - release that version
- `/release patch|minor` - bump that part

## Rules

- **Confirm before each step that leaves this machine**: pushing master, pushing the tag, and
  `gh release create`. Show what is about to go out. An instruction from the user that names the
  step ("push master and the tag") is the confirmation.
- Never force-push, never `rake release`, never `rake push`, never approve the `release`
  environment. The user approves the publish in GitHub.
- The repository is public. Nothing published may name a private consumer app, its UI gem or their
  org. The names are in the user's memory (`private-consumer-names`); if it is not loaded, read it
  before step 7. Use AGENTS.md's placeholders (`app-a`, `app-b`, `app-c`, `ui-gem`).
- `gh` needs the sandbox off (`dangerouslyDisableSandbox: true`). Watch a run with a background
  Bash loop that prints `gh` errors, not a Monitor.

## Steps

### 1. Preflight

```bash
git status -sb                       # on master, clean, level with origin/master
git fetch -q --tags origin
PREV=$(git describe --tags --abbrev=0); echo "$PREV"
git log --oneline "$PREV"..HEAD
```

Stop if the tree is dirty, the branch is not master, or master is behind origin.

### 2. Dependencies (only when asked, or offered once if the last update is older than the last tag)

Per AGENTS.md's Gotchas: `bundle update --all`, the same with `BUNDLE_GEMFILE` for each
`gemfiles/*.gemfile`, and `bundle update --all --local` in `fixtures/adopted` (move its pinned
Rails to the main lock's first). For Go, `GOWORK=off go get -u ./...`, then
`go get go@<current go line>` to undo any `go` line raise, and esbuild-internal's newest tag by
date (`git tag --sort=-creatordate` in `../esbuild-internal`). Run every lane (step 5's list),
then commit as `build: ...`.

### 3. Choose the version

Read every commit since `$PREV` (`git log --format='%h %s%n%b' "$PREV"..HEAD`). Versions follow
[SemVer](https://semver.org): a breaking change bumps **major**, a new feature **minor**, and a
release of fixes alone **patch**. While the major version is 0, a breaking change bumps **minor**
instead, as 0.26.0 did; 1.0.0 happens only when the user asks for it. A breaking change is a
removed or renamed public constant, require path, config option or CLI flag, or a change to
behaviour an app relies on. Say which bump and why in one line. To find removals, diff the public
surface:

```bash
git diff "$PREV"..HEAD --name-status -- lib exe
git diff "$PREV"..HEAD -- lib/proscenium.rb | grep -E '^[-+]\s*(autoload|require|[A-Z_]+ =)'
```

### 4. Bump and commit

The version lives in `lib/proscenium/version.rb` and six lockfile lines: `proscenium (x.y.z)` in
`Gemfile.lock`, each `gemfiles/*.gemfile.lock`, and twice in `fixtures/adopted/Gemfile.lock`.

```bash
OLD=<current>; NEW=<new>
sed -i '' "s/VERSION = '$OLD'/VERSION = '$NEW'/" lib/proscenium/version.rb
sed -i '' "s/proscenium ($OLD/proscenium ($NEW/" Gemfile.lock gemfiles/*.gemfile.lock fixtures/adopted/Gemfile.lock
grep -rn "proscenium ($OLD" Gemfile.lock gemfiles/*.gemfile.lock fixtures/adopted/Gemfile.lock   # must print nothing
grep -c "proscenium ($NEW" Gemfile.lock gemfiles/*.gemfile.lock fixtures/adopted/Gemfile.lock    # 1,1,1,1,2
bundle exec rubocop lib/proscenium/version.rb
git commit -qam "chore(release): $NEW" -m "<the commit trailer the session asks for>"
git tag -a "v$NEW" -m "v$NEW"
```

No CHANGELOG: the GitHub release is the changelog.

### 5. Push master and wait for CI

After confirmation, `git push origin master` (not the tag yet). Watch the `main` workflow run for
that SHA until it completes; every job must pass. On a failure, stop and report the failing job and
its log tail; do not tag over a red master.

If anything that builds the gems changed since `$PREV` (`go.mod`, the `Rakefile`, `release.yml`,
`bin/verify-*`), offer a dry run first:
`gh workflow run release.yml --ref master -f dry_run=true`, and watch it to completion.

### 6. Push the tag and watch the release run

After confirmation, `git push origin "v$NEW"`. Find the run
(`gh run list --workflow release.yml --limit 2`) and poll it until its status is `waiting` (the
`release` environment's approval gate) or a job fails. Report each job's conclusion, then tell the
user it is waiting for their approval.

### 7. Write the release notes

Draft them to the scratchpad as `release-notes-v$NEW.md`, from the commits since `$PREV`. Match the
previous releases (`gh release view $PREV --json body -q .body`):

- `## Breaking changes` first, when there are any. Each removed constant or require path, with what
  replaces it (a table when there are several), and what an app has to change.
- `## Features`, `## Fixes` (grouped under `###` areas when there are more than a few), then
  `## Documentation` if a doc change alters what users do.
- Each item opens with a **bold sentence saying what now happens**, then what a user saw before.
  Plain language, no internal names (finding IDs, audit rows, PR-only jargon).
- Leave out what users cannot see: tests, CI, refactors with no behaviour change, audit and backlog
  docs, and any change a later commit in the same range reverts.

Before showing the draft:

1. Scrub it: grep it for every name in `private-consumer-names`, and read each `platform` hit.
2. For each breaking change, check the consumers named in that memory and the public gems
   (`~/dev/proscenium-phlex`, `~/dev/proscenium-view_component`, `~/dev/proscenium-ui`): fetch, then
   `git grep` their default branch for the removed names, with a control count of `Proscenium::`
   so an empty result is shown to be real. Report usage to the user only, never in the notes.

Show the user the path and a summary, and wait for their go-ahead.

### 8. Publish the notes

After confirmation:

```bash
gh release create "v$NEW" --title "v$NEW" --notes-file <path> --verify-tag
gh release view "v$NEW" --json url,isDraft,publishedAt
```

Then grep the published body (`gh release view "v$NEW" --json body -q .body`) for the private names
once more. When the user has approved the publish job, confirm the gems are live:
`curl -s https://rubygems.org/api/v1/versions/proscenium.json` lists `$NEW` for every platform.

### 9. Report

Version, the release commit and tag, the CI and release run URLs, the release URL, and anything
skipped (dependency update, dry run) with why.
