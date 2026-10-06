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
          :input, '%<detail>s',
          'Run `bundle exec proscenium --help` to see the commands and their options.'
        ],
        'PSM-E-GEMSPEC' => [
          :input, 'Expected one gemspec in %<path>s, but found %<found>s.',
          "Run `proscenium gem check` from the gem's own directory, or pass it that directory " \
          'or a built .gem file.'
        ],
        'PSM-E-NOT-OPTED-IN' => [
          :input, '%<gem>s has not opted in to having Proscenium install its NPM ' \
                  'dependencies.',
          "Add `spec.metadata['proscenium.dependencies'] = 'true'` to its gemspec."
        ],
        'PSM-E-FRONTEND-ROOT' => [
          :input, "%<gem>s's proscenium.frontend_root (%<root>s) points outside the gem.",
          "Set proscenium.frontend_root to a directory inside the gem, relative to the gem's root."
        ],
        'PSM-E-MANIFEST' => [
          :input, "%<gem>s's %<path>s can't be used, because %<cause>s.",
          'Ship a valid package.json there: a JSON object whose dependency fields map package ' \
          'names to version strings.'
        ],
        'PSM-E-GEM-FILES' => [
          :input, "%<gem>s's gemspec doesn't list %<files>s in spec.files, so the built gem " \
                  "won't include it.",
          'Add package.json, and every frontend file the gem serves, to spec.files.'
        ],
        'PSM-E-NAME' => [
          :input, "The gem name %<gem>s can't be used as a JavaScript package name " \
                  '(@rubygems/%<gem>s).',
          'JavaScript package names use only lowercase letters, digits and - . _ ~, are at most ' \
          "214 characters long, and can't end in a dot or be a Windows device name such as con " \
          'or nul. The gem needs a valid name before Proscenium can install its dependencies.'
        ],
        'PSM-E-WORKSPACES' => [
          :input, "%<gem>s's package.json declares workspaces, which a gem's package.json " \
                  "can't do.",
          "Remove \"workspaces\" from the gem's package.json."
        ],
        'PSM-E-HOOK' => [
          :input, '%<gem>s needs build steps at install time (%<hooks>s), and Proscenium never ' \
                  'runs them.',
          "Ship the gem's assets already built, and remove those install-time hooks."
        ],
        'PSM-E-SPEC' => [
          :input, "%<gem>s depends on %<name>s as \"%<spec>s\", which Proscenium doesn't allow.",
          'Use a version range or tag, an npm:<package> alias, a github:, git+https: or git+ssh: ' \
          'URL, or an https: tarball URL.'
        ],
        'PSM-E-CREDENTIAL' => [
          :input, "%<gem>s's dependency %<name>s has a password or token in its URL, which " \
                  'would be committed to your repository.',
          'Remove it from the URL. Apps log in to private registries in their own .npmrc.'
        ],
        'PSM-E-ALIAS' => [
          :input, "%<gem>s aliases %<name>s to \"%<spec>s\", which is another gem's " \
                  'dependency context.',
          "Add the other gem to the gemspec's dependencies, and use @rubygems/<gem> directly."
        ],
        'PSM-E-REACT' => [
          :input, '%<gem>s lists %<packages>s as dependencies, so it would get its own copy and ' \
                  'the page would load two.',
          "List %<packages>s under peerDependencies instead, so the gem uses the app's copy."
        ],
        'PSM-E-CROSS-GEM' => [
          :input, "%<gem>s's package.json uses @rubygems/%<other>s, but its gemspec doesn't " \
                  'depend on the %<other>s gem.',
          "Add `spec.add_dependency '%<other>s'` to the gemspec, or stop using " \
          '@rubygems/%<other>s.'
        ],
        'PSM-E-NO-MANAGER' => [
          :input, "Proscenium can't tell which package manager this app uses: there is no " \
                  'packageManager field in package.json, and no pnpm-lock.yaml or bun.lock.',
          'Run again with --manager pnpm or --manager bun, or add a packageManager field to ' \
          'package.json.'
        ],
        'PSM-E-MANAGER-CONFLICT' => [
          :input, 'This app points to more than one package manager: %<signals>s.',
          'Keep just one: delete the other lockfile, or make packageManager in package.json ' \
          'match the lockfile. (--manager only decides when nothing else does.)'
        ],
        'PSM-E-UNSUPPORTED-MANAGER' => [
          :unsupported, 'This app uses %<manager>s, but Proscenium can only install ' \
                        "gems' NPM dependencies with pnpm or Bun.",
          "Switch the app to pnpm or Bun, or keep adding gems' NPM dependencies to " \
          'package.json yourself.'
        ],
        'PSM-E-BUN-LOCKB' => [
          :unsupported, "This app only has bun.lockb, Bun's older binary lockfile, which " \
                        "Proscenium can't read.",
          'Run `bun install --save-text-lockfile` to write bun.lock, then commit it.'
        ],
        'PSM-E-MANAGER-MISSING' => [
          :unsupported, "%<manager>s isn't installed, or isn't on your PATH.",
          'Install %<manager>s the way this project normally does (Corepack, mise, Volta or its ' \
          'own installer), then try again.'
        ],
        'PSM-E-MANAGER-VERSION' => [
          :unsupported, "Proscenium doesn't support %<manager>s %<version>s.",
          'Use a supported version of %<manager>s (%<supported>s). To experiment locally with ' \
          'another, add --experimental-manager-version.'
        ],
        'PSM-E-EXPERIMENTAL-FROZEN' => [
          :unsupported, "--experimental-manager-version can't be combined with --frozen.",
          'Use a supported package manager version wherever --frozen runs, such as CI.'
        ],
        'PSM-E-BUN-LINKER' => [
          :unsupported, "bunfig.toml doesn't say which linker Bun uses (hoisted or isolated), " \
                        'and adding gem dependency contexts could make Bun switch linkers.',
          'Add `linker = "hoisted"` (or "isolated", whichever your app uses today) to the ' \
          '`[install]` table in bunfig.toml, creating the table if there is none.'
        ],
        'PSM-E-NESTED-WORKSPACE' => [
          :unsupported, 'This app is inside the JavaScript workspace at %<enclosing>s, and ' \
                        "Proscenium doesn't support that yet.",
          "Keep adding gems' NPM dependencies to that workspace yourself, as you do today."
        ],
        'PSM-E-REGISTRATION' => [
          :input, "Proscenium couldn't add the gem dependency contexts to %<file>s without " \
                  'rewriting the file.',
          'Check that %<file>s is valid (package.json must be strict JSON, with no comments or ' \
          'trailing commas). Then add ".proscenium/packages/*" yourself, to `packages` in ' \
          'pnpm-workspace.yaml or `workspaces` in package.json, and run ' \
          '`bundle exec proscenium install` again.'
        ],
        'PSM-E-REGISTRATION-EXCLUDED' => [
          :input, '%<file>s excludes .proscenium/packages/ with a "!" pattern, so your package ' \
                  'manager would never install the gem dependency contexts.',
          'Remove that pattern from %<file>s, then run `bundle exec proscenium install` again.'
        ],
        'PSM-E-BUSY' => [
          :busy, '%<holder>s is already running in this project.',
          'Wait for it to finish, then run your command again. If nothing is actually ' \
          'installing, delete .proscenium/manager, which an earlier run left behind.'
        ],
        'PSM-E-NATIVE' => [
          :native, '`%<command>s` failed (exit status %<status>s).',
          'Its output is above. Fix what it reports, then run `bundle exec proscenium install` ' \
          "again. Proscenium hasn't changed your package manager or regenerated your lockfile."
        ],
        'PSM-E-INTERRUPTED' => [
          :interrupted, '`%<command>s` was stopped before it finished.',
          'Run `bundle exec proscenium install` again to finish.'
        ],
        'PSM-E-CROSS-GEM-TARGET' => [
          :input, "%<gem>s's package.json uses @rubygems/%<other>s, but %<other>s hasn't " \
                  'opted in to having Proscenium install its NPM dependencies.',
          'Opt %<other>s in: its author adds proscenium.dependencies to its gemspec, or you add ' \
          '`"proscenium": {"gemOverrides": {"%<other>s": {"participate": true}}}` to your ' \
          'package.json.'
        ],
        'PSM-E-CONFIG' => [
          :input, "Proscenium can't read its settings: %<detail>s.",
          'Fix package.json. Proscenium reads one setting from it: ' \
          '`"proscenium": {"gemOverrides": {"<gem>": {"participate": true}}}`, with true or ' \
          'false for each gem.'
        ],
        'PSM-E-PROBLEMS' => [
          :input, 'The install stopped because of the problems above. Nothing was changed.',
          'Fix each one as it says, then run `bundle exec proscenium install` again.'
        ],
        'PSM-E-DRIFT' => [
          :drift, "Some files are out of date with your bundle:\n%<list>s",
          'Run `bundle exec proscenium install`, then commit the files it lists.'
        ],
        'PSM-E-NOT-REGISTERED' => [
          :drift, "%<file>s doesn't list .proscenium/packages/*, so %<manager>s won't install " \
                  "your gems' NPM dependencies.",
          'Run `bundle exec proscenium install`, then commit %<file>s.'
        ],
        'PSM-E-GITIGNORE' => [
          :drift, ".gitignore is missing some of Proscenium's lines, or a later rule hides the " \
                  'dependency contexts you need to commit.',
          'Run `bundle exec proscenium install` to add them, then commit .gitignore.'
        ],
        'PSM-E-LOCKFILE-MISSING' => [
          :drift, '%<lockfile>s is missing.',
          'Run `bundle exec proscenium install`, then commit %<lockfile>s.'
        ],
        'PSM-E-NOT-INSTALLED' => [
          :drift, "Your NPM dependencies aren't installed: there is no node_modules " \
                  'directory.',
          'Run `bundle exec proscenium install`, or `bundle exec proscenium install --frozen` on ' \
          'a fresh checkout or in CI.'
        ],
        'PSM-E-REGISTRY-TARBALL' => [
          :integrity, 'The lockfile installs %<packages>s from a registry or Git, instead of ' \
                      'from the gem itself.',
          'Remove the registry or GitHub dependency on it from your package.json, since ' \
          'Gemfile.lock provides the gem now, then run `bundle exec proscenium install`.'
        ],
        'PSM-E-WORKSPACE-MISSING' => [
          :integrity, "%<manager>s didn't install the dependency contexts for %<gems>s.",
          'Check that `packages` in pnpm-workspace.yaml, or `workspaces` in package.json, ' \
          'lists ".proscenium/packages/*", then run `bundle exec proscenium install` again.'
        ],
        'PSM-E-PEER-SPLIT' => [
          :integrity, '%<gem>s and your app use different copies of %<package>s, so the page ' \
                      'would load it twice.',
          "Change your app's %<package>s to a version within %<gem>s's peer range, then run " \
          '`bundle exec proscenium install` again.'
        ],
        'PSM-E-COLLISION' => [
          :input, "Some of your app's dependencies use a name a gem's dependency context " \
                  "needs:\n%<list>s",
          'Remove each one, since Gemfile.lock provides the gem now, or rename the package.'
        ],
        'PSM-E-BUN-DEFAULT-TRUSTED' => [
          :unsupported, "`bun pm default-trusted` didn't print Bun's default list of trusted " \
                        "packages, so Proscenium can't check whose install scripts Bun would run.",
          'Add `"trustedDependencies": []` to package.json, listing any packages whose install ' \
          'scripts your app needs, so Bun uses that list instead of its default.'
        ],
        'PSM-E-TRUSTED-SOURCE' => [
          :input, 'Some gems install a package from Git, a URL or an alias to another package, ' \
                  'under a name your package manager trusts to run install scripts, so that ' \
                  "code's install script would run:\n%<list>s",
          "Ask the gem's author to depend on the registry package instead, or opt the gem out " \
          'with `"proscenium": {"gemOverrides": {"<gem>": {"participate": false}}}` in ' \
          'package.json. pnpm trusts the packages pnpm-workspace.yaml approves builds for; Bun ' \
          'trusts trustedDependencies in package.json, or its own default list without one.'
        ],
        'PSM-E-PLATFORM-VARIANT' => [
          :unsupported, 'The platform-specific builds of %<variants>s differ from the one ' \
                        'installed here in their NPM dependencies or whether they opt ' \
                        "in, or don't pass `proscenium gem check`.",
          'Make every platform build of the gem ship the same package.json dependencies and ' \
          'proscenium.dependencies setting, each passing `proscenium gem check`. Your lockfile ' \
          'can only hold one set.'
        ],
        'PSM-E-UNC-SHIM' => [
          :unsupported, "%<manager>s is installed as a .cmd script, and cmd.exe can't run in " \
                        "%<root>s because it's a network (UNC) path: it would run in " \
                        'C:\\Windows instead.',
          'Map a drive letter to the share (`net use Z: \\\\server\\share`) and run from that ' \
          'drive, or install %<manager>s as a native executable.'
        ],
        'PSM-E-OWNED-LINK' => [
          :input, '%<paths>s is a symbolic link, so installing would write outside your app.',
          'Replace it with a real directory. Proscenium only writes inside .proscenium/.'
        ],
        'PSM-E-OWNED-DIR' => [
          :input, ".proscenium/packages/ contains things Proscenium didn't create: %<entries>s.",
          'Move them somewhere else. Proscenium manages that directory, and treats everything ' \
          'in it as a gem dependency context.'
        ],
        'PSM-W-END-OF-LIFE' => [
          :success, '%<manager>s %<version>s reaches end of life on %<eol>s, and a future ' \
                    'Proscenium release may stop supporting it.',
          'Plan an upgrade to a newer %<manager>s version; the upgrade guide explains the steps.'
        ],
        'PSM-E-INTERNAL' => [
          :internal, 'Something went wrong inside Proscenium: %<detail>s',
          'This is a bug in Proscenium. Please report it at ' \
          'https://github.com/joelmoss/proscenium/issues, including the output above.'
        ]
      }.freeze

      attr_reader :code, :fix, :details
      # What the package manager printed, for a native failure: not shown, only searched.
      attr_accessor :output

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
