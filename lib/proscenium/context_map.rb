# frozen_string_literal: true

require 'bundler'
require 'json'
require_relative 'bundled_gems'

module Proscenium
  # What the engine passes Go about gem dependency contexts (#154): which gems resolve their bare
  # imports from `.proscenium/packages/<gem>/`, and which of the app's own packages keep their link
  # paths. Built from committed files and Bundler only. Like BundledGems, it loads nothing the
  # `proscenium` CLI may not.
  module ContextMap
    CONTEXTS = File.join('.proscenium', 'packages')
    REGISTRATION = '.proscenium/packages/*'
    LOCAL_SPECS = %w[link: file: workspace: portal:].freeze

    module_function

    # Where the `proscenium` CLI keeps contexts, its lock and its marker: the bundle's root, which
    # need not be Rails.root.
    def project_root = Bundler.root.to_s

    # The config keys Go reads, for the app at `root`. Read once per mapping generation: a value
    # read during an older one is kept under that one's key, never handed to the next.
    def config(root, generation = 0)
      @config ||= {}
      @config[[root, generation]] ||= { DependencyContexts: contexts(root),
                                        AppLocalPackages: local_packages(root) }.freeze
    end

    def reset! = @config = {}

    # Whether the app at `root` adopted gem dependency contexts: pnpm's workspace file registers
    # them, or package.json does in a Bun app. Yarn and npm apps never have.
    def adopted?(root)
      registers?(root, 'pnpm-workspace.yaml') ||
        (File.exist?(File.join(root, 'bun.lock')) && registers?(root, 'package.json'))
    end

    def registers?(root, file)
      path = File.join(root, file)
      File.exist?(path) && File.read(path).include?(REGISTRATION)
    end

    # Gem name => absolute context directory for each participating gem, when the app at `root`
    # adopted dependency contexts; empty before. A gem whose context is missing is mapped all the
    # same: its imports then fail by name rather than fall back to the app's packages.
    def contexts(root, specs = BundledGems.installed_specs)
      return {} unless adopted?(root)

      BundledGems.participating(specs, overrides: BundledGems.overrides(root)).keys.to_h do |gem|
        [gem, File.join(root, CONTEXTS, gem)]
      end
    end

    INSTALLING = File.join('.proscenium', 'installing')
    LOCK = File.join('.proscenium', 'lock')
    INSTALLING_MESSAGE = '`bundle exec proscenium install` is running, or stopped before it ' \
                         'finished. Wait for it, or run it again.'

    # Whether an install is under way in the app at `root`, or stopped before it finished: its
    # marker is there, or another process holds the project lock. The engine refuses to build or
    # resolve meanwhile (C34). The probe takes a shared lock, so it never stops an install
    # starting; the CLI retries a lock it finds taken for a moment. About 16 µs.
    def installing?(root)
      return true if File.exist?(File.join(root, INSTALLING))

      lock = File.join(root, LOCK)
      File.exist?(lock) && File.open(lock, File::RDONLY) { !it.flock(File::LOCK_SH | File::LOCK_NB) }
    end

    UNSUPPORTED = { 'yarn.lock' => 'Yarn', 'package-lock.json' => 'npm',
                    'npm-shrinkwrap.json' => 'npm' }.freeze

    # The one notice a process logs at boot when gems opt in but the app has not adopted dependency
    # contexts, or nil. Those gems' imports keep resolving as they always have, so upgrading
    # Proscenium never breaks an app that has not run `proscenium install` (C52).
    def adoption_notice(root, specs = BundledGems.installed_specs)
      return if adopted?(root)

      gems = BundledGems.participating(specs, overrides: BundledGems.overrides(root)).keys
      return if gems.empty?

      opted = "#{gems.join(', ')} opt in to installing their JavaScript dependencies " \
              'through Proscenium'
      manager = UNSUPPORTED.find { |file, _| File.exist?(File.join(root, file)) }&.last
      if manager
        "#{opted}, but #{manager} is not supported, so the app keeps managing them."
      else
        "#{opted}. Run `bundle exec proscenium install` to install them."
      end
    rescue BundledGems::ConfigError => e
      e.message
    end

    # The names of the app's own `link:`, `file:` and workspace dependencies. They keep their link
    # paths once dependency contexts make other packages real-path.
    def local_packages(root)
      path = File.join(root, 'package.json')
      return [] unless File.exist?(path)

      package = JSON.parse(File.read(path))
      %w[dependencies devDependencies optionalDependencies].flat_map do |field|
        (package[field] || {}).select { |_, spec| spec.to_s.start_with?(*LOCAL_SPECS) }.keys
      end.uniq.sort
    rescue JSON::ParserError
      []
    end
  end
end
