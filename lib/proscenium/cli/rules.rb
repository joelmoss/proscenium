# frozen_string_literal: true

module Proscenium
  module CLI
    # The author contract for a participating gem's package.json (#154): what `gem check` and
    # `install` refuse. Each rule yields a problem as [error code, format arguments]; the caller
    # decides whether a problem is fatal and how to word the escape.
    module Rules
      DEPENDENCY_FIELDS = %w[dependencies peerDependencies optionalDependencies].freeze
      HOOKS = %w[preinstall install postinstall prepare].freeze
      REACT = %w[react react-dom].freeze
      # Problems install reports as warnings: the gem still gets its context.
      WARNINGS = %w[PSM-E-REACT].freeze

      # npm's rules for a package name, as `@rubygems/<gem>` must satisfy them: lowercase, so no two
      # contexts can differ only in case, and at most 214 characters.
      VALID_NAME = %r{\A@rubygems/[a-z0-9][a-z0-9._~-]*\z}
      NAME_LIMIT = 214

      # Names Windows reserves for devices, with or without an extension: COM1-COM9 and LPT1-LPT9,
      # not COM0 or LPT0. A context directory so named cannot exist there, so the gem is refused on
      # every host alike (C27).
      RESERVED = /\A(?:con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\..*)?\z/

      # URL specs Proscenium accepts. With RANGE_OR_TAG and npm: aliases, these are the only specs
      # accepted; anything else is refused.
      GIT_URL = %r{\A(?:github:[\w.-]+/[\w.-]+|git\+(?:https|ssh)://\S+)(?:#\S+)?\z}
      TARBALL = %r{\Ahttps://\S+\z}
      # A `user:password` before the host of any URL, anything before the host of an http(s) URL
      # (a token), or a token-like query parameter. `git+ssh://git@host` names the SSH user, not a
      # credential.
      CREDENTIAL = Regexp.union(%r{://[^/@\s]*:[^/@\s]*@}, %r{https?://[^/@\s]*@}i,
                                /[?&][^=&#]*(?:token|key|auth|pass|secret|sig)[^=&#]*=/i)
      # A semver range or a dist-tag. Everything else a manager would read as a path, a Git
      # repository or a protocol, so it is refused.
      RANGE_OR_TAG = /\A(?:[\w*^~<>=|+.-]|(?<=\S) (?=\S))*\z/
      # `npm:<package>[@<range or tag>]`: a registry package by npm's name rules, never a path,
      # link or URL.
      ALIAS = %r{\Anpm:(?<name>(?:@[a-z0-9][\w.~-]*/)?[a-z0-9][\w.~-]*)(?:@(?<range>.*))?\z}mi

      module_function

      # Problems with the manifest of `gem`, rooted at `root` (where binding.gyp would be), and
      # named `path` in errors. `binding_gyp` says a built gem, which has no root on disk, ships
      # one.
      def check(gem, manifest, root: nil, path: 'package.json', binding_gyp: false)
        shape = shape_problem(manifest)
        return [['PSM-E-MANIFEST', { gem:, path:, cause: shape }]] if shape

        problems = []
        problems << ['PSM-E-NAME', { gem: }] unless valid_name?(gem)
        problems << ['PSM-E-WORKSPACES', { gem: }] if manifest.key?('workspaces')

        hooks = HOOKS & (manifest['scripts'] || {}).keys
        binding_gyp ||= root && File.exist?(File.join(root, 'binding.gyp'))
        hooks << 'binding.gyp' if binding_gyp
        problems << ['PSM-E-HOOK', { gem:, hooks: hooks.join(', ') }] if hooks.any?

        DEPENDENCY_FIELDS.each do |field|
          (manifest[field] || {}).each do |name, spec|
            problem = spec_problem(gem, name, spec)
            problems << problem if problem
          end
        end

        # An optional dependency is the gem's own copy too, and so is React under an alias.
        react = REACT & %w[dependencies optionalDependencies].flat_map do |field|
          (manifest[field] || {}).flat_map { |name, spec| [name, ALIAS.match(spec)&.[](:name)] }
        end
        problems << ['PSM-E-REACT', { gem:, packages: react.join(' and ') }] if react.any?
        problems
      end

      # Why a field every rule reads is the wrong type, or nil. Checked first, so nothing after it
      # meets a string where it expects an object.
      def shape_problem(manifest)
        %w[scripts peerDependenciesMeta].each do |field|
          return "#{field} is not an object" unless [Hash, NilClass].include?(manifest[field].class)
        end
        DEPENDENCY_FIELDS.each do |field|
          deps = manifest[field]
          next if deps.nil?
          return "#{field} is not an object" unless deps.is_a?(Hash)

          name = deps.find { |_, spec| !spec.is_a?(String) }&.first
          return "#{field}.#{name} is not a string" if name
        end
        nil
      end

      # Each "<gem>: <name> (<spec>)" whose name the app trusts but whose spec is not that registry
      # package: Git, a URL, or an alias to another package. Bun trusts a dependency by name,
      # whatever its source (probed on Bun 1.4.2), so a gem could run its own install script under
      # the app's trust. `manifests` is each gem's parsed context.
      def trusted_substitutions(trusted, manifests)
        substitutions(manifests).filter_map do |gem, name, spec|
          "#{gem}: #{name} (#{spec})" if trusted == :all || trusted.include?(name)
        end
      end

      # Each [gem, name, spec] that is not that registry package: Git, a URL, or an alias to
      # another package.
      def substitutions(manifests)
        manifests.flat_map do |gem, manifest|
          DEPENDENCY_FIELDS.flat_map { (manifest[it] || {}).to_a }.filter_map do |name, spec|
            [gem, name, spec] if substitutes?(name, spec)
          end
        end
      end

      def substitutes?(name, spec)
        target = ALIAS.match(spec)&.[](:name)
        GIT_URL.match?(spec) || TARBALL.match?(spec) || (target && target.downcase != name.downcase)
      end

      def valid_name?(gem)
        name = "@rubygems/#{gem}"
        VALID_NAME.match?(name) && name.length <= NAME_LIMIT && !RESERVED.match?(gem) &&
          !gem.end_with?('.')
      end

      # Larger than any real package.json, small enough to read without a second thought.
      MANIFEST_LIMIT = 1024 * 1024

      # Why the package.json at `path`, in a gem rooted at `gem_root`, cannot be read safely, or
      # nil (C29): it must be a regular file, inside the gem once links are followed, and no larger
      # than MANIFEST_LIMIT. A FIFO or device would block or never end, and a link out of the gem
      # would read a file the gem does not ship.
      def manifest_file_problem(path, gem_root)
        return 'it is not a regular file' unless File.file?(path)

        real = File.realpath(path)
        return 'it links outside the gem' unless real.start_with?("#{File.realpath(gem_root)}/")
        return 'it is larger than 1 MB' if File.size(real) > MANIFEST_LIMIT

        nil
      end

      # Why `spec` for dependency `name` is refused, or nil. A gem-to-gem reference
      # (`@rubygems/<other>`) is checked against the bundle at install time, not here.
      def spec_problem(gem, name, spec)
        return nil if name.start_with?('@rubygems/')

        # A credential in a URL would be committed with the context (C31). A server decodes
        # percent-escapes, so `%74oken=` is `token=`.
        if [spec, unescape(spec)].any? { CREDENTIAL.match?(it) }
          return ['PSM-E-CREDENTIAL', { gem:, name: }]
        end

        if spec.start_with?('npm:')
          return ['PSM-E-ALIAS', { gem:, name:, spec: }] if spec.start_with?('npm:@rubygems/')

          target = ALIAS.match(spec)
          return if target && range_or_tag?(target[:range].to_s)

          return ['PSM-E-SPEC', { gem:, name:, spec: }]
        end
        return nil if GIT_URL.match?(spec) || TARBALL.match?(spec) || range_or_tag?(spec)

        ['PSM-E-SPEC', { gem:, name:, spec: }]
      end

      def unescape(spec) = spec.gsub(/%(\h\h)/) { ::Regexp.last_match(1).hex.chr }

      # A leading dot is a path to every manager, though the characters are a range's.
      def range_or_tag?(spec) = RANGE_OR_TAG.match?(spec) && !spec.start_with?('.')
    end
  end
end
