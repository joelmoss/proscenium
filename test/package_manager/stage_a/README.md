# Package-manager fixture gems (#154)

Synthetic gems the package-manager tests install the way an app gets them: genuinely, through
Bundler, into a throwaway, read-only bundle. They started as #154's Stage A proof, which is why
they keep the `stage_a_` prefix; the proof's results are in
`docs/plans/154-package-manager-stage-a.md`.

## Layout

| Path | What it is |
|---|---|
| `gems/` | Sources of the fixture gems |
| `bundle.rb` | `StageA::Bundle.install(dir)`: builds the archive gems, installs every fixture gem with Bundler into `dir/bundle`, makes it read-only, and returns `{ name => installed root }` |

Used by `test/cli/install_test.rb`, `test/cli/spec_kinds_test.rb`, `test/cli/gem_check_test.rb`,
`test/bun_layout_test.rb`, `test/adopted/`, `test/first_run_test.rb` and
`test/context_wiring_test.rb`, and by `fixtures/adopted`'s Gemfile.

## Fixture gems

| Gem | Installed as | Opted in | Shape |
|---|---|---|---|
| `stage_a_assets` | archive | no | JS and CSS with relative imports, no package.json. The control: a gem that does not participate. |
| `stage_a_app_dependent` | path, in `fixtures/adopted` only | no | A gem that relies on the app for its JavaScript dependencies. |
| `stage_a_widget_a` | archive | yes | React `^18.3.1` peer, ms 2.0.0 |
| `stage_a_widget_b` | archive | yes | React `^18.3.1` peer, ms 2.1.3 |
| `stage_a_specs` | archive, built by `spec_kinds_test.rb` with `Bundle.build` | yes | Every dependency spec kind: ranges, `npm:` aliases, a dist-tag, `github:`, a tarball URL. |
| `gem_npm` | archive | yes | The repository's `fixtures/dummy/vendor/gem_npm` (string-length `^6.0.0`) |
| `stage_a_hue_shape` | Git | yes | ui-gem's traits: package.json without `version`, `react` and `react-dom` as plain dependencies, a `github:` dependency, and package.json missing from `spec.files`. Its Ruby version is a prerelease (`0.5.3.pre1`). |

Archive gems are built with `Gem::Package.build` and installed with `bundle install --local` from
the app's `vendor/cache`, so there is no gem index and no network. `stage_a_hue_shape` comes from a
local Git repository, because only a Git checkout keeps a manifest that `spec.files` leaves out.
The installed `bundle/` is made read-only (`a-w`); `StageA::Bundle.writable!` undoes it for
cleanup.

`is-number` is one of Proscenium's browser-native replacements
(`internal/replacements/src/is-number.mjs`): the engine swaps the import out before any
resolution, so the widgets conflict on `ms` 2.0.0 and 2.1.3 instead.

- **`stage_a_assets` does not opt in.** An opted-in gem with no manifest is a participation
  error, and the tests need a gem that does not participate.
- **`gem_npm` gets its file list and opt-in at build time**, in `bundle.rb`, not in its gemspec.
  The dummy app loads that gemspec as a path gem, and would otherwise treat it as a participant.

`stage_a_hue_shape`'s `github:` dependency is `sindresorhus/escape-string-regexp` at the v5.0.0
commit: public, small, and with no install scripts. It is not one of ui-gem's own dependencies, so
the fixture copies ui-gem's shape without copying its manifest.
