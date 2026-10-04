# #154 guide drafts

Drafts of the two guides the plan asks for at the end of Stage A: the consumer quickstart and the
gem author guide. They describe the CLI the plan specifies, which does not exist until Stage B, so
the commands below are the contract, not something to run today. Each draft says what Stage A
exercised against its fixtures. They are published, with real transcripts, in Stage E.

## Quickstart: JavaScript dependencies from gems

Some gems ship frontend code with a package.json of its own. Proscenium installs those
dependencies with your app's package manager, pnpm or Bun, and resolves each gem's imports from
them. The gem's files stay where Bundler installed them.

1. Add the gem and install it with Bundler:

   ```sh
   bundle add some_ui_gem
   ```

2. Install its JavaScript dependencies:

   ```sh
   bundle exec proscenium install
   ```

   The first run registers `.proscenium/packages/*` with your package manager (pnpm-workspace.yaml,
   or `workspaces` in package.json for Bun) and adds three `.gitignore` lines, printing both as a
   diff before it writes them. On Bun it also pins the linker your app uses today in bunfig.toml,
   in the same diff, since registering workspaces would otherwise switch it. It needs an explicit
   `trustedDependencies` in package.json, and stops once to tell you to add one if it is missing:
   only you can say which packages' scripts your app relies on.

3. Commit what it lists: each `.proscenium/packages/<gem>/package.json`, the registration,
   `.gitignore` and your lockfile.

Run `bundle exec proscenium install` again after every Gemfile change. In CI, run
`bundle exec proscenium install --frozen`, which writes nothing and fails if anything is out of
date. A plain `pnpm install` or `bun install` also works on a fresh checkout, because the contexts
are committed.

Only gems that opt in take part. A gem that ships a package.json without opting in keeps working
as it does today; `bundle exec proscenium inspect` lists them, and `proscenium.json` can opt one in:

```json
{ "schema": 1, "gemOverrides": { "some_ui_gem": { "participate": true } } }
```

**Exercised in Stage A** by hand on london and platform (pnpm) and codaset (Bun), and from the
fixture gems in CI: the registration on a fresh app and spliced into an existing
pnpm-workspace.yaml, the contexts, frozen installs, and imports resolving from the contexts.

### When the engine refuses to build

Once an app has adopted, the engine checks its contexts against the bundle. While any is stale it
refuses every build and names the gem and `bundle exec proscenium install`. A context is stale when
a participating gem has none, its gem left Gemfile.lock or stopped participating, the gem's
dependencies changed since it was written, or a shared peer such as React split into two copies.
Development logs this once at boot and shows it on the error page. `assets:precompile` refuses too,
which is how a deploy with stale contexts fails. For an incident, `PROSCENIUM_STALE_CONTEXT=warn`
logs it instead. While `proscenium install` runs, or after one stopped before it finished, the
engine refuses to build until the install completes; running it again recovers.

In development, finishing an install or editing a path gem's package.json takes effect within a
second, without a restart. Adding or upgrading a gem still needs one, as it always has.

### Import only what your app declares

A gem's dependencies are the gem's. Under pnpm, and Bun's isolated linker, a package only a gem
declares never reaches your app's own `node_modules`, so importing it from app code fails. Under
Bun's hoisted linker it does reach it, so such an import works by accident and breaks the day the
gem drops that dependency. Add what your app imports to your own package.json.

### Deploying

- Run `bundle exec proscenium install --frozen` (or a frozen native install) before
  `assets:precompile`. Restart after the deploy: production reads the contexts once per process.
- Unbundled pages load packages from their real paths: pnpm's store under `/node_modules/.pnpm/`,
  Bun's isolated store under `/node_modules/.bun/`, and a copy a linker nested under a context from
  `/.proscenium/packages/<gem>/node_modules/...`. A proxy rule that denies dotfile paths (nginx's
  common `location ~ /\.`) blocks all three. Allow those prefixes ahead of it, or bundle in
  production. For nginx, with `app` as your upstream:

  ```nginx
  location ^~ /node_modules/.pnpm/ { proxy_pass http://app; }
  location ^~ /node_modules/.bun/ { proxy_pass http://app; }
  location ^~ /.proscenium/packages/ { proxy_pass http://app; }
  location ~ /\. { deny all; }
  ```

  `^~` makes nginx take those prefixes without checking the regular expression.
- The contexts live at the bundle's root, beside the Gemfile. When that is not the Rails root, a
  nested copy has no URL under the app and keeps its link path.

**Exercised in Stage C** by `fixtures/adopted`, a Rails app that ran `proscenium install`: a gem's
dependency from its context beside the app's own version, one React shared, gems that do not
participate served as before, an archive gem, precompiling, the refusals, and `bun test`.

## Gem author guide

### Checklist

`proscenium gem check` runs this list; run it before every release.

1. Opt in: `spec.metadata['proscenium.dependencies'] = 'true'`.
2. Put package.json and every frontend file in `spec.files`. A Git-source install keeps files
   outside `spec.files`, a built gem does not, so a manifest missing from it works for some users
   and not others.
3. Declare every package your frontend code imports. A missing one is an error naming your gem
   and the package, not a silent miss.
4. Declare React, and anything else the app must share, as a peer, not a dependency.
5. Use only semver ranges, dist-tags, `npm:` aliases, `github:` and `git+https:`/`git+ssh:` URLs,
   tarball URLs, or a gem you depend on in your gemspec. No `file:`, `link:` or `workspace:`.
6. Ship built assets. Proscenium never runs your install, prepare or build scripts, and a Git
   dependency that needs `prepare` stops a pnpm install until the app approves it.
7. Leave `version` out or stale if you like: the context does not copy it.

### An example package.json

```json
{
  "name": "@rubygems/some_ui_gem",
  "dependencies": { "ms": "^2.1.3" },
  "peerDependencies": { "react": "^18.3.1" }
}
```

### What the app commits for your gem

```json
{
  "name": "@rubygems/some_ui_gem",
  "private": true,
  "dependencies": { "ms": "^2.1.3" },
  "peerDependencies": { "react": "^18.3.1" },
  "description": "Generated by Proscenium from the some_ui_gem gem. Do not edit; run bundle exec proscenium install.",
  "proscenium": { "projection": "dependency-context-v1", "projectionSha256": "<hex>" }
}
```

**Exercised in Stage A** against the fixture gems: `stage_a_widget_a` and `stage_a_widget_b` pass
every item; `stage_a_hue_shape` fails items 2 and 4 by design (package.json outside `spec.files`,
React as a dependency), as hue does; `stage_a_assets` does not opt in and is left alone. Against a
real gem, proscenium-ui fails item 3 (it imports `react`, `clsx` and `trix` without declaring
them), which the Stage A seam reported by name.

Still to write for Stage E: the first-run transcript, a sample pull-request diff, a Dockerfile
layering example, the CI recipe and the `bin/setup` line, all from the real CLI.
