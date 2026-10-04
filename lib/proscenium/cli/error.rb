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
        'PSM-E-INTERNAL' => [
          :internal, 'Unexpected error: %<detail>s',
          'This is a bug in Proscenium. Please report it at ' \
          'https://github.com/joelmoss/proscenium/issues with the output above.'
        ]
      }.freeze

      attr_reader :code, :fix, :details

      def initialize(code, details: {}, **args)
        @code = code
        status, message, fix = CATALOG.fetch(code)
        @status = status
        @fix = format(fix, **args)
        @details = details
        super(format(message, **args))
      end

      def exit_status = EXIT.fetch(@status)
    end
  end
end
