# frozen_string_literal: true

require 'bundler'
require 'json'
require_relative 'app_package'
require_relative 'bundled_gems'
require_relative 'yaml_tree'

module Proscenium
  # What the engine passes Go about gem dependency contexts (#154): which gems resolve their bare
  # imports from `.proscenium/packages/<gem>/`, and which of the app's own packages keep their link
  # paths. Built from committed files and Bundler only. Like BundledGems, it loads nothing the
  # `proscenium` CLI may not.
  module ContextMap
    CONTEXTS = File.join('.proscenium', 'packages')
    REGISTRATION = '.proscenium/packages/*'

    module_function

    # Where the `proscenium` CLI keeps contexts, its lock and its marker: the bundle's root, which
    # need not be Rails.root.
    def project_root = Bundler.root.to_s

    # The config keys Go reads, for the app at `root`. Read once per mapping generation: a value
    # read during an older one is kept under that one's key, never handed to the next.
    def config(root, generation = 0)
      @config ||= {}
      @config[[root, generation]] ||= { DependencyContexts: contexts(root),
                                        AppLocalPackages: AppPackage.local_packages(root) }.freeze
    end

    def reset! = @config = {}

    # Each registering file, with the lockfile and the name of the manager that reads it.
    REGISTRARS = { 'pnpm-workspace.yaml' => %w[pnpm-lock.yaml pnpm],
                   'package.json' => %w[bun.lock bun] }.freeze

    # Whether the app at `root` adopted gem dependency contexts: pnpm's workspace file registers
    # them, or package.json does in a Bun app. Each counts only where its manager installs: when
    # packageManager names no other manager, and with that manager's lockfile or no other
    # manager's, as an app missing its lockfile is an incomplete checkout, which must not silently
    # switch the contexts off.
    def adopted?(root) = !registrar(root).nil?

    # The file whose registration makes the app at `root` adopted, or nil.
    def registrar(root)
      named = AppPackage.package_manager(root)
      REGISTRARS.find do |file, (own, manager)|
        # bun.lockb is Bun's too, until bun.lock replaces it.
        others = [*UNSUPPORTED.keys, *REGISTRARS.values.map(&:first)] - [own] +
                 (manager == 'bun' ? [] : ['bun.lockb'])
        registers?(root, file) && [nil, manager].include?(named) &&
          (File.exist?(File.join(root, own)) || others.none? { File.exist?(File.join(root, it)) })
      end&.first
    end

    # Whether `file` lists the contexts: pnpm-workspace.yaml's `packages`, or package.json's
    # `workspaces` (an array, or an object's `packages`). Parsed, so a commented-out line does not
    # count. For the engine a file that does not parse counts if it names them, so a parse failure
    # never silently switches off the context map and the stale check; `strict` (the CLI, which
    # must register a file its manager can read) counts only a file that parses.
    def registers?(root, file)
      path = File.join(root, file)
      File.exist?(path) && registered_in?(file, File.read(path))
    end

    def registered_in?(file, text, strict: false)
      text = utf8(text).delete_prefix(BOM)
      list = file.end_with?('.yaml') ? yaml_packages(text) : json_workspaces(text)
      list.is_a?(Array) && list.any? { registration?(it) } && !excludes?(list)
    rescue Psych::SyntaxError, JSON::ParserError
      return false if strict

      file.end_with?('.yaml') ? text.include?(REGISTRATION) : AppPackage.workspaces?(text)
    end

    # Whether the list has a `!` pattern that takes a context out: pnpm and Bun apply one whatever
    # its order, so the contexts would never be installed. Generous: `*` crosses `/`, and any
    # segment of the pattern may be a gem's directory.
    def excludes?(list)
      Array(list).grep(/\A!/).any? do |entry|
        pattern = entry[1..].delete_prefix('./').chomp('/')
        # A segment with a wildcard, class or brace, such as `[ah]ue`, may match any gem.
        wide = pattern.split('/').map { it.match?(/[*?\[{]/) ? '*' : it }.join('/')
        ['gem', *pattern.split('/')].product([pattern, wide]).any? do |name, glob|
          File.fnmatch?(glob, "#{CONTEXTS}/#{name}", GLOB)
        end
      end
    end

    GLOB = File::FNM_EXTGLOB | File::FNM_DOTMATCH

    def json_workspaces(text)
      parsed = JSON.parse(text)
      list = parsed['workspaces'] if parsed.is_a?(Hash)
      list.is_a?(Hash) ? list['packages'] : list
    end

    # pnpm-workspace.yaml's `packages`: each entry's scalar text, or nil for one that is not a
    # scalar; nil when the document is not a mapping or the key is missing or not a list. Read from
    # the parse tree and never built into Ruby objects, so no alias can make it slow and no tag or
    # date can raise. Raises Psych::SyntaxError.
    def yaml_packages(text)
      list, anchors = YamlTree.value(text, 'packages')
      return unless list.is_a?(Psych::Nodes::Sequence)

      list.children.map do |entry|
        entry = YamlTree.node(entry, anchors)
        entry.value if entry.is_a?(Psych::Nodes::Scalar)
      end
    end

    # pnpm and Bun read `./<pattern>` and `<pattern>/` as the pattern.
    def registration?(entry)
      entry.is_a?(String) && entry.delete_prefix('./').chomp('/') == REGISTRATION
    end

    BOM = "\uFEFF"

    # A JSON file as Node, pnpm and Bun read it, a leading byte order mark included.
    def read_json(path) = parse_json(File.read(path))
    def parse_json(text) = JSON.parse(utf8(text).delete_prefix(BOM))

    # Text as UTF-8, whatever encoding the caller's locale gave it.
    def utf8(text) = text.dup.force_encoding(Encoding::UTF_8)

    # Gem name => absolute context directory for each participating gem, when the app at `root`
    # adopted dependency contexts; empty before. A gem whose context is missing is mapped all the
    # same: its imports then fail by name rather than fall back to the app's packages.
    def contexts(root, specs = BundledGems.installed_specs)
      return {} unless adopted?(root)

      BundledGems.participating(specs, overrides: BundledGems.overrides(root)).keys.to_h do |gem|
        [gem, File.join(root, CONTEXTS, gem)]
      end
    rescue BundledGems::ConfigError
      {} # StaleContexts reports it, so every build is refused with the reason
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

    # Each file that says the app uses an unsupported manager, as Manager.select reads them.
    UNSUPPORTED = { 'yarn.lock' => 'Yarn', '.yarnrc.yml' => 'Yarn', 'package-lock.json' => 'npm',
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
  end
end
