# Stage A proof (#154)

The disposable proof that a gem's JavaScript dependencies can be installed into a dependency-only
context and resolved from it, while the gem's own files stay at the root Bundler installed. The
contract is the "Stage A execution contract" section of `docs/plans/154-package-manager.md`.
Results go in `docs/plans/154-package-manager-stage-a.md`. Nothing here is production code:
Stage B and C replace it.

## Layout

| Path | What it is |
|---|---|
| `gems/` | Sources of the synthetic fixture gems |
| `bundle.rb` | `StageA::Bundle.install(dir)`: builds the archive gems, installs every fixture gem with Bundler into `dir/bundle`, makes it read-only, and returns `{ name => installed root }` |
| `bundle_test.rb` | What each installed gem ships, and that its root is read-only |
| `../../stage_a_seam_test.go` | The resolver seam against a pnpm-shaped tree |

## Fixture gems

| Gem | Installed as | Opted in | Shape |
|---|---|---|---|
| `stage_a_assets` | archive | no | JS and CSS with relative imports, no package.json. The control: a gem that does not participate. |
| `stage_a_widget_a` | archive | yes | React `^18.3.1` peer, ms 2.0.0 |
| `stage_a_widget_b` | archive | yes | React `^18.3.1` peer, ms 2.1.3 |
| `gem_npm` | archive | yes | The repository's `fixtures/dummy/vendor/gem_npm` (string-length `^6.0.0`) |
| `stage_a_hue_shape` | Git | yes | hue's traits: package.json without `version`, `react` and `react-dom` as plain dependencies, a `github:` dependency, and package.json missing from `spec.files`. Its Ruby version is a prerelease (`0.5.3.pre1`). |

Archive gems are built with `Gem::Package.build` and installed with `bundle install --local` from
the app's `vendor/cache`, so there is no gem index and no network. `stage_a_hue_shape` comes from a
local Git repository, because only a Git checkout keeps a manifest that `spec.files` leaves out.
The installed `bundle/` is made read-only (`a-w`); `StageA::Bundle.writable!` undoes it for
cleanup.

The plan names is-number 6.0.0 and 7.0.0 for the widgets, but `is-number` is one of Proscenium's
browser-native replacements (`internal/replacements/src/is-number.mjs`): the engine swaps the
import out before any resolution, so the version conflict would never reach a context. The
widgets use `ms` 2.0.0 and 2.1.3 instead, which is not replaced.

Two readings of the plan, recorded here so they are not mistaken for accidents:

- **`stage_a_assets` does not opt in.** The fixture paragraph says each fixture sets
  `proscenium.dependencies`, but an opted-in gem with no manifest is a participation error, and
  C01 needs a gem that does not participate. It is the control.
- **`gem_npm` gets its file list and opt-in at build time**, in `bundle.rb`, not in its gemspec.
  The dummy app loads that gemspec as a path gem, and Stage C would otherwise start treating it
  as a participant.

`stage_a_hue_shape`'s `github:` dependency is `sindresorhus/escape-string-regexp` at the v5.0.0
commit: public, small, and with no install scripts. It is not one of hue's own dependencies, so
the fixture copies hue's shape without copying its manifest.

## The resolver seam

`ConfigT.StageAContexts` (Go) maps a gem name to the absolute path of its hand-written context,
`.proscenium/packages/<gem>/`. It does nothing unless set, and only Stage A sets it. For a
mapped gem:

- A bare import resolves from the context directory, replacing the whole existing chain. That
  includes its first step, whose walk-up from an in-tree gem reaches the app's `node_modules`
  first. Hooked at `bundler.go` (bundled), the `bundless.go` resolve chain and its
  bare-with-extension shortcut, the bundless asset loader (CSS modules and SVG by package name),
  and `resolver.Resolve`, which CSS mixins go through.
- Ordinary `node_modules` walk-up from the context still applies, as the plan's Lookup section
  says: it is how hoisted copies are found. So a package only the app declares still resolves
  for the gem. A spec pins that, and step 2 records what each real layout does with it.
- A package nothing provides is an error naming the gem and the package, never a browser
  external.
- While the seam is on, a resolved path under `node_modules/` or `.proscenium/packages/` is
  replaced by its real path (`utils.StageARealPath`), so the app and a gem reach a shared React
  at one URL when unbundling. Bundled builds get this from esbuild already.

Each of those has a spec in `test/stage_a_seam_test.go`, and each spec was checked to fail with
its part of the seam removed.

Known limit: the real-path rule compares against `RootPath` as text, so the root must itself be
a real path. On macOS a temporary directory under `/var` is really under `/private/var`; the
specs evaluate the root first.

**Getting the map into a running app (decided, built in step 4).** `Proscenium::Builder.new`
merges keyword overrides straight into the Go config, so Ruby-level probes pass
`StageAContexts:` directly. The browser identity probe needs the middleware's builder, which
takes no overrides: step 4 adds one line to `Builder#initialize` passing
`Proscenium.config.stage_a_contexts` (nil, so absent, unless a probe app sets it in an
initializer), and the same key to the Bun daemon's handshake in `runtime/server.rb`.

## Tool probes (4 October 2026)

A `git+file://` dependency on a local bare repository, whose package has a `postinstall` script:

| Manager | Installs it | Runs the script |
|---|---|---|
| pnpm 10.34.4 | yes | no (blocked, build approval needed) |
| Bun 1.4.2 | yes, with a full or short SHA | no (`Blocked 1 postinstall`) |
| Bun 1.3.13 | no: `no commit matching "<sha>" found` | n/a |

So the hermetic fixtures can serve Git dependencies from a local bare repository on both
supported lines. A `github:` specifier itself cannot be redirected there; step 2 decides whether
the CI copy of `stage_a_hue_shape` uses `git+file://` and only the local hue leg keeps `github:`.

## The app legs (steps 2 and 3)

`probe/` is a Go command that builds a list of entry points through the engine, with the seam on
or off, and records the modules or imports each one pulls in. `leg.rb` drives it against copies
of an app's JS configuration and the local checkout of the gem its bundle points at, on pnpm or
Bun:

```sh
ruby test/package_manager/stage_a/leg.rb ~/dev/clients/harleytherapy/london \
  ~/dev/clients/harleytherapy/hue CONFIG tmp/stage_a_london
ruby test/package_manager/stage_a/leg.rb ~/dev/codaset ~/dev/proscenium-ui CONFIG \
  tmp/stage_a_codaset
```

CONFIG is a local JSON file naming the gem, the manager, and the app's entry points, aliases and
externals (the script's header gives the format); the apps' configuration stays out of this
repository. It writes only under the output directory, which it refuses to delete unless it made
it. The CI half of the london leg is `hue_shape_test.rb`: the same check for `stage_a_hue_shape`,
through `Proscenium::Builder`, run by the `stage-a` CI job and locally with
`STAGE_A=1 bin/test test/package_manager/stage_a/`. The codaset leg's CI half is `bun_test.rb`:
where Bun's hoisted and isolated linkers put the widgets' conflicting `ms` copies, what each widget
then builds against, and that an explicit `trustedDependencies` blocks a gem-introduced package
Bun trusts by default. They write contexts with `context.rb`. The
verdicts are in `docs/plans/154-package-manager-stage-a.md`.

## Not yet built

- The contexts for these fixtures, the hermetic registry and committed tarballs, and
  proscenium-ui at a pinned revision.
- The browser identity probe and the `Builder`/daemon wiring above (step 4).
