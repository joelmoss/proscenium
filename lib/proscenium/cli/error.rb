# frozen_string_literal: true

module Proscenium
  module CLI
    # Every failure the CLI reports: a stable code, the exit status it maps to, and text that states
    # the problem, its cause and the fix. The catalog is the single source; golden-output tests pin
    # the human text and the JSON event for each entry (test/cli/golden/).
    class Error < StandardError
      EXIT = { success: 0, internal: 1, input: 2, unsupported: 3, drift: 4, integrity: 5,
               native: 6, busy: 7, interrupted: 8 }.freeze

      # code => [exit, message template, fix template]. Templates take keyword arguments.
      CATALOG = {
        'PSM-E-USAGE' => [
          :input, '%<detail>s', 'Run `bundle exec proscenium --help` for usage.'
        ],
        'PSM-E-GEMSPEC' => [
          :input, 'Expected one gemspec in %<path>s, found %<found>s.',
          "Run `proscenium gem check` in the gem's directory, or pass that directory or a " \
          'built .gem.'
        ],
        'PSM-E-NOT-OPTED-IN' => [
          :input, '%<gem>s does not opt in to JavaScript dependency installation.',
          "Add `spec.metadata['proscenium.dependencies'] = 'true'` to the gemspec."
        ],
        'PSM-E-FRONTEND-ROOT' => [
          :input, "%<gem>s's proscenium.frontend_root (%<root>s) is outside the gem.",
          'Set proscenium.frontend_root to a directory inside the gem, relative to its root.'
        ],
        'PSM-E-MANIFEST' => [
          :input, "%<gem>s's %<path>s cannot be used: %<cause>s.",
          'Ship a package.json that is a JSON object at that path.'
        ],
        'PSM-E-GEM-FILES' => [
          :input, '%<gem>s does not list %<files>s in spec.files, so a built gem leaves it out.',
          'Add the package.json and every frontend file to spec.files in the gemspec.'
        ],
        'PSM-E-NAME' => [
          :input, '%<gem>s cannot be a JavaScript package: @rubygems/%<gem>s is not a valid ' \
                  'npm name.',
          'npm names are lowercase letters, digits, and - . _ ~. Rename the gem to participate.'
        ],
        'PSM-E-WORKSPACES' => [
          :input, "%<gem>s's package.json declares workspaces, which a gem cannot.",
          'Remove "workspaces" from the gem\'s package.json.'
        ],
        'PSM-E-HOOK' => [
          :input, '%<gem>s needs install-time build steps (%<hooks>s), which Proscenium ' \
                  'never runs.',
          'Ship built assets in the gem and remove the install, prepare and native build hooks.'
        ],
        'PSM-E-SPEC' => [
          :input, '%<gem>s depends on %<name>s as "%<spec>s", a kind of dependency ' \
                  'Proscenium refuses.',
          'Use a semver range, a dist-tag, an npm: alias, a github: or git+https: URL, or an ' \
          'https: tarball.'
        ],
        'PSM-E-ALIAS' => [
          :input, '%<gem>s aliases %<name>s to "%<spec>s", a gem context.',
          'Depend on the gem in the gemspec and reference @rubygems/<gem> directly.'
        ],
        'PSM-E-REACT' => [
          :input, '%<gem>s declares %<packages>s as dependencies, so it would get its own copy.',
          'Declare %<packages>s as peerDependencies, so the gem shares the app\'s.'
        ],
        'PSM-E-CROSS-GEM' => [
          :input, "%<gem>s's package.json references @rubygems/%<other>s, but its gemspec does " \
                  'not depend on %<other>s.',
          "Add `spec.add_dependency '%<other>s'` to the gemspec, or remove the reference."
        ],
        'PSM-E-NO-MANAGER' => [
          :input, 'No package manager is set: no packageManager field, pnpm-lock.yaml or bun.lock.',
          'Pass --manager pnpm or --manager bun, or add a packageManager field to package.json.'
        ],
        'PSM-E-MANAGER-CONFLICT' => [
          :input, 'The project names more than one package manager: %<signals>s.',
          'Keep one: remove the other lockfile, or make packageManager match the lockfile. ' \
          '--manager chooses only when nothing else says.'
        ],
        'PSM-E-UNSUPPORTED-MANAGER' => [
          :unsupported, 'This project uses %<manager>s, which Proscenium does not support for ' \
                        "gems' JavaScript dependencies.",
          'Switch the app to pnpm or Bun, or keep installing gems\' JavaScript dependencies ' \
          'yourself, as today.'
        ],
        'PSM-E-BUN-LOCKB' => [
          :unsupported, 'This project has only a binary bun.lockb, which Proscenium cannot read.',
          'Run `bun install --save-text-lockfile` to write bun.lock, and commit it.'
        ],
        'PSM-E-MANAGER-MISSING' => [
          :unsupported, '%<manager>s is not installed, or not on PATH.',
          'Install %<manager>s the way this project expects (Corepack, mise, Volta or its ' \
          'installer), then try again.'
        ],
        'PSM-E-MANAGER-VERSION' => [
          :unsupported, '%<manager>s %<version>s is not a version Proscenium supports.',
          'Use a supported %<manager>s (%<supported>s). --experimental-manager-version allows ' \
          'another for development only.'
        ],
        'PSM-E-EXPERIMENTAL-FROZEN' => [
          :unsupported, '--experimental-manager-version cannot be used with --frozen.',
          'Use a supported manager version in CI, where --frozen runs.'
        ],
        'PSM-E-BUN-LINKER' => [
          :unsupported, "bunfig.toml does not set Bun's linker, so registering gem contexts " \
                        'could switch it.',
          'Add `[install]` and `linker = "hoisted"` (or "isolated", whichever the app uses ' \
          'today) to bunfig.toml.'
        ],
        'PSM-E-BUN-TRUSTED' => [
          :unsupported, 'package.json has no trustedDependencies, so Bun would run install ' \
                        'scripts of packages gems introduce, from its default list.',
          'Add `"trustedDependencies": []` to package.json, listing any packages whose scripts ' \
          'the app already relies on.'
        ],
        'PSM-E-NESTED-WORKSPACE' => [
          :unsupported, 'This app is inside the JavaScript workspace at %<enclosing>s, which ' \
                        'Proscenium does not support.',
          'Install gems\' JavaScript dependencies yourself in that workspace, as today.'
        ],
        'PSM-E-REGISTRATION' => [
          :input, 'Could not add the gem contexts to %<file>s without rewriting it.',
          'Add ".proscenium/packages/*" to the workspaces in %<file>s by hand, then run install ' \
          'again.'
        ],
        'PSM-E-BUSY' => [
          :busy, '%<holder>s is already running in this project.',
          'Wait for it to finish, then run `bundle exec proscenium install` again.'
        ],
        'PSM-E-NATIVE' => [
          :native, '`%<command>s` failed with exit status %<status>s.',
          'Its output is above. Fix what it reports, then run `bundle exec proscenium install` ' \
          'again; Proscenium has not changed your manager or regenerated your lockfile.'
        ],
        'PSM-E-INTERRUPTED' => [
          :interrupted, '`%<command>s` was interrupted before it finished.',
          'Run `bundle exec proscenium install` again to finish the install.'
        ],
        'PSM-E-CROSS-GEM-TARGET' => [
          :input, "%<gem>s's package.json references @rubygems/%<other>s, which does not take " \
                  'part in JavaScript dependency installation.',
          'Opt %<other>s in: its author sets proscenium.dependencies, or the app adds ' \
          '`"gemOverrides": {"%<other>s": {"participate": true}}` to proscenium.json.'
        ],
        'PSM-E-CONFIG' => [
          :input, '%<detail>s.',
          'Fix proscenium.json; its documented keys are schema, gemOverrides, rubyGroups and ' \
          'platforms.'
        ],
        'PSM-E-PROBLEMS' => [
          :input, '%<count>s problem(s) above stop the install. Nothing was changed.',
          'Fix each one as it says, then run `bundle exec proscenium install` again.'
        ],
        'PSM-E-DRIFT' => [
          :drift, "%<count>s thing(s) differ from what the bundle calls for:\n%<list>s",
          'Run `bundle exec proscenium install` and commit what it lists.'
        ],
        'PSM-E-REGISTRY-TARBALL' => [
          :integrity, 'The lockfile resolves %<packages>s from a registry, not from the gem.',
          'Remove the registry or GitHub dependency on it from package.json, then run ' \
          '`bundle exec proscenium install`.'
        ],
        'PSM-E-WORKSPACE-MISSING' => [
          :integrity, '%<manager>s did not install the contexts for %<gems>s.',
          'Check the registration in pnpm-workspace.yaml or package.json names ' \
          '".proscenium/packages/*", then run `bundle exec proscenium install` again.'
        ],
        'PSM-E-PEER-SPLIT' => [
          :integrity, '%<gem>s and the app resolve %<package>s to different copies, so the ' \
                      'page would load it twice.',
          'Make the app and %<gem>s agree on %<package>s. On pnpm 10, `pnpm dedupe` usually ' \
          'repairs this after an upgrade; `auto-install-peers=false` in .npmrc prevents it.'
        ],
        'PSM-E-INTERNAL' => [
          :internal, 'Unexpected error: %<detail>s',
          'This is a bug in Proscenium. Please report it at ' \
          'https://github.com/joelmoss/proscenium/issues with the output above.'
        ]
      }.freeze

      attr_reader :code, :fix, :details

      # `escape`, when given, is the consumer's way around a gem author's problem, appended to the
      # fix.
      def initialize(code, details: {}, escape: nil, **args)
        @code = code
        status, message, fix = CATALOG.fetch(code)
        @status = status
        @fix = [format(fix, **args), escape].compact.join(' ')
        @details = details
        super(format(message, **args))
      end

      def exit_status = EXIT.fetch(@status)
    end
  end
end
