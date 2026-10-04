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

      # npm's rules for a package name, as `@rubygems/<gem>` must satisfy them: lowercase, so no two
      # contexts can differ only in case, and at most 214 characters.
      VALID_NAME = %r{\A@rubygems/[a-z0-9][a-z0-9._~-]*\z}
      NAME_LIMIT = 214

      # Names Windows reserves for devices, with or without an extension. A context directory so
      # named cannot exist there, so the gem is refused on every host alike (C27).
      RESERVED = /\A(?:con|prn|aux|nul|com[0-9]|lpt[0-9])(?:\..*)?\z/

      # Specs Proscenium accepts. Anything with a protocol not listed is refused.
      GIT_URL = %r{\A(?:github:[\w.-]+/[\w.-]+|git\+(?:https|ssh)://\S+)(?:#\S+)?\z}
      TARBALL = %r{\Ahttps://\S+\z}
      PROTOCOL = /\A[a-z][a-z0-9+.-]*:/i
      # A user and a password before the host: `scheme://user:password@host`.
      CREDENTIAL = %r{://[^/@\s]*:[^/@\s]*@}

      module_function

      # Problems with the manifest of `gem`, rooted at `root` (where binding.gyp would be).
      def check(gem, manifest, root: nil)
        problems = []
        problems << ['PSM-E-NAME', { gem: }] unless valid_name?(gem)
        problems << ['PSM-E-WORKSPACES', { gem: }] if manifest.key?('workspaces')

        hooks = HOOKS & (manifest['scripts'] || {}).keys
        hooks << 'binding.gyp' if root && File.exist?(File.join(root, 'binding.gyp'))
        problems << ['PSM-E-HOOK', { gem:, hooks: hooks.join(', ') }] if hooks.any?

        DEPENDENCY_FIELDS.each do |field|
          (manifest[field] || {}).each do |name, spec|
            problem = spec_problem(gem, name, spec.to_s)
            problems << problem if problem
          end
        end

        react = REACT & (manifest['dependencies'] || {}).keys
        problems << ['PSM-E-REACT', { gem:, packages: react.join(' and ') }] if react.any?
        problems
      end

      def valid_name?(gem)
        name = "@rubygems/#{gem}"
        VALID_NAME.match?(name) && name.length <= NAME_LIMIT && !RESERVED.match?(gem)
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

        if spec.start_with?('npm:')
          target = spec.delete_prefix('npm:')
          return ['PSM-E-ALIAS', { gem:, name:, spec: }] if target.start_with?('@rubygems/')

          return nil
        end
        # A password in a URL would be committed with the context (C31).
        return ['PSM-E-CREDENTIAL', { gem:, name: }] if CREDENTIAL.match?(spec)
        return nil if GIT_URL.match?(spec) || TARBALL.match?(spec)
        return ['PSM-E-SPEC', { gem:, name:, spec: }] if PROTOCOL.match?(spec)

        nil # a semver range or a dist-tag
      end
    end
  end
end
