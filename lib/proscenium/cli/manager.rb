# frozen_string_literal: true

require 'json'
require_relative '../context_map'
require_relative '../yaml_tree'
require_relative 'pnpm_approvals'
require 'open3'
require 'bundler'
require 'date'

module Proscenium
  module CLI
    # Which package manager a project uses, whether Proscenium supports it, and whether the project
    # is set up to register contexts with it (#154). Nothing here writes: every refusal happens
    # before `install` changes a file.
    class Manager
      CAPABILITIES = JSON.parse(File.read(File.expand_path('capabilities.json', __dir__)))
      SUPPORTED = %w[pnpm bun].freeze
      # Lockfile => the manager that writes it. LOCKFILES.key(name) is a manager's own lockfile.
      LOCKFILES = { 'pnpm-lock.yaml' => 'pnpm', 'bun.lock' => 'bun', 'yarn.lock' => 'yarn',
                    'package-lock.json' => 'npm', 'npm-shrinkwrap.json' => 'npm' }.freeze
      LINKERS = %w[hoisted isolated].freeze

      attr_reader :name, :version, :executable, :root

      # Selects the manager for the project at `root`: `requested` (from --manager), else the root
      # package.json's `packageManager`, else exactly one recognized lockfile.
      def self.select(root, requested: nil)
        requested ||= from_package_manager(root)
        lockfiles = LOCKFILES.select { |file, _| File.exist?(File.join(root, file)) }.values.uniq
        lockfiles << 'yarn' if File.exist?(File.join(root, '.yarnrc.yml'))
        lockfiles.uniq!

        name = requested || lockfiles.first
        # Every lockfile is its manager's, whichever manager is named; bun.lockb is Bun's too.
        lockb = File.exist?(File.join(root, 'bun.lockb'))
        signals = [requested, *lockfiles, ('bun' if lockb)].compact.uniq
        if signals.size > 1
          raise Error.new('PSM-E-MANAGER-CONFLICT', signals: signals.join(' and '))
        end
        # However Bun is chosen, a binary bun.lockb is its only lock until bun.lock is written.
        if lockb && !lockfiles.include?('bun') && [nil, 'bun'].include?(name)
          raise Error, 'PSM-E-BUN-LOCKB'
        end
        raise Error, 'PSM-E-NO-MANAGER' unless name
        raise Error.new('PSM-E-UNSUPPORTED-MANAGER', manager: name) unless SUPPORTED.include?(name)

        new(name, root)
      end

      # The manager named by package.json's `packageManager` (`pnpm@10.33.1+sha512...`), or nil.
      def self.from_package_manager(root)
        path = File.join(root, 'package.json')
        return nil unless File.exist?(path)

        field = ContextMap.read_json(path)['packageManager']
        field.is_a?(String) ? field.split('@').first : nil
      rescue JSON::ParserError
        nil
      end

      def initialize(name, root)
        @name = name
        @root = root
      end

      # Checks the installed manager's version against the capability table. An unqualified
      # version is refused unless `experimental`, which `frozen` never allows.
      def check_version!(experimental: false, frozen: false)
        @executable = self.class.which(@name) or raise Error.new('PSM-E-MANAGER-MISSING',
                                                                 manager: @name)
        check_launchable!
        # pnpm runs the version packageManager pins or refuses to run; Bun ignores the field, so
        # Bun's own answer is the only one that counts.
        @version = (@name == 'pnpm' && runs_pin? && pinned_version) || probed_version
        return self if line

        raise Error, 'PSM-E-EXPERIMENTAL-FROZEN' if experimental && frozen
        unless experimental
          raise Error.new('PSM-E-MANAGER-VERSION', manager: @name, version: @version,
                                                   supported: supported_ranges)
        end

        self
      end

      # The capability table's line for the installed version, or nil. A prerelease, such as
      # `12.0.0-beta.1`, belongs to no line.
      def line
        return if @version.to_s.match?(/\A\d+(?:\.\d+)*-/)

        version = Gem::Version.new(@version.to_s[/\A\d+(?:\.\d+)*/] || '0')
        CAPABILITIES.dig('managers', @name, 'lines').find do |line|
          Gem::Requirement.new(*line['range'].split(',').map(&:strip)).satisfied_by?(version)
        end
      end

      # A warning when the installed line's owner stops maintaining it within six months: the
      # next Proscenium release may no longer support it.
      def end_of_life_warning(today: Date.today)
        eol = line && line['eol']
        return nil unless eol && Date.parse(eol) - today <= 183

        Error.new('PSM-W-END-OF-LIFE', manager: @name, version: @version, eol:)
      end

      def supported_ranges
        CAPABILITIES.dig('managers', @name, 'lines').map { it['range'] }.join('; ')
      end

      # A `.cmd` or `.bat` shim, as npm installs pnpm, runs under cmd.exe, which cannot use a UNC
      # path as its working directory: it falls back to C:\Windows and runs the manager there
      # (C27). So a project reached through a UNC path needs a native executable or a drive.
      def check_launchable!
        return unless @executable.match?(/\.(?:cmd|bat)\z/i) && self.class.unc?(@root)

        raise Error.new('PSM-E-UNC-SHIM', manager: @name, root: @root)
      end

      # The version a `--version` run printed. Only stdout, and its last line that is one: the first
      # run of a pinned manager also prints that it is downloading it.
      def self.version_in(output)
        output.lines.map(&:strip).grep(/\A\d+\.\d+\.\d+\S*\z/).last || output.strip
      end

      # The version package.json's packageManager pins for this manager, or nil. pnpm runs exactly
      # that version or refuses to run, so it is the one install gets, and reading it runs nothing:
      # pnpm 12 writes pnpm-lock.yaml on any command in a pinned project, `--version` included, so
      # probing would change the project before install could refuse anything.
      def pinned_version
        path = File.join(@root, 'package.json')
        field = File.exist?(path) && ContextMap.read_json(path)['packageManager']
        return unless field.is_a?(String)

        name, version = field.split('+').first.split('@', 2)
        version if name == @name && version
      rescue JSON::ParserError
        nil
      end

      # Whether pnpm runs only the version packageManager pins: it downloads it (pmOnFail
      # `download`, the default) or refuses to run (`error`). With `warn` or `ignore`, from the
      # environment or pnpm-workspace.yaml, it runs whatever is installed, and probing it writes
      # nothing.
      def runs_pin?
        setting = PnpmApprovals.env('pm_on_fail') || workspace_setting('pmOnFail')
        !%w[warn ignore].include?(setting)
      end

      def workspace_setting(key)
        path = File.join(@root, 'pnpm-workspace.yaml')
        return unless File.exist?(path)

        text = ContextMap.utf8(File.read(path)).delete_prefix(ContextMap::BOM)
        value, = YamlTree.value(text, key)
        value.value if value.is_a?(Psych::Nodes::Scalar)
      rescue Psych::SyntaxError
        nil
      end

      def probed_version
        out, status = Bundler.with_unbundled_env do
          Open3.capture2(@executable, '--version', chdir: @root)
        end
        raise Error.new('PSM-E-MANAGER-MISSING', manager: @name) unless status.success?

        self.class.version_in(out)
      end

      def self.unc?(path) = path.start_with?('//', '\\\\')

      # Bun registers contexts only in a project that has chosen its linker explicitly: without
      # one, registering a workspace can switch the app to another linker. A missing linker is
      # written by registration (BunLinker), so only `frozen`, which writes nothing, refuses it;
      # an unknown one is always refused.
      def check_project!(frozen: false)
        check_not_nested!
        return self unless @name == 'bun'

        # Registration adds an [install] table, which Bun refuses beside one already set inline.
        linker = bun_linker
        refused = linker ? !LINKERS.include?(linker) : frozen || inline_install?
        raise Error, 'PSM-E-BUN-LINKER' if refused

        package_json
        self
      end

      # The app's package.json, or nil. Bun reads a trailing comma that Ruby refuses, and so would
      # registration, so a file that is not strict JSON is refused here, before any write.
      def package_json
        path = File.join(@root, 'package.json')
        File.exist?(path) ? ContextMap.read_json(path) : nil
      rescue JSON::ParserError
        raise Error.new('PSM-E-REGISTRATION', file: 'package.json')
      end

      # The names whose install scripts the manager runs. pnpm: those pnpm-workspace.yaml approves
      # builds for, or :all when it allows every build. Bun: package.json's trustedDependencies, or
      # without one, Bun's own default list, as the installed Bun prints it.
      def trusted_names
        if @name == 'pnpm'
          return PnpmApprovals.allow_all?(@root) ? :all : PnpmApprovals.names(@root)
        end

        package = package_json
        listed = package['trustedDependencies'] if package.is_a?(Hash)
        return listed.grep(String) if listed.is_a?(Array)

        out, status = Bundler.with_unbundled_env do
          Open3.capture2(@executable, 'pm', 'default-trusted', chdir: @root)
        end
        names = status.success? ? out.lines.filter_map { it[/\A - (\S+)\s*\z/, 1] } : []
        # An empty list would let a gem reach any default-trusted name, so it is refused.
        raise Error, 'PSM-E-BUN-DEFAULT-TRUSTED' if names.empty?

        names
      end

      # bunfig.toml's `install` table name, bare or quoted.
      INSTALL = /(?:install|"install"|'install')/
      LINKER = /(?:linker|"linker"|'linker')\s*=\s*["']([^"']*)["']/
      TABLE_LINKER = /\A#{LINKER}\z/
      # Before any table: `install.linker = "…"`, or `install = { …, linker = "…" }`.
      TOP_LEVEL_LINKER = /\A#{INSTALL}\s*(?:\.\s*#{LINKER}\z|=\s*\{(?:.*,)?\s*#{LINKER}\s*[,}])/
      INLINE_INSTALL = /\A#{INSTALL}\s*[.=]/

      # The `linker` bunfig.toml sets for Bun's `install` table, or nil.
      def bun_linker
        table = nil
        bunfig_lines.each do |line|
          if (header = line[/\A\[\s*([^\]]+?)\s*\]\z/, 1])
            table = header.delete(%q('"))
          elsif (value = linker_on(line, table))
            return value
          end
        end
        nil
      end

      def linker_on(line, table)
        return line[TABLE_LINKER, 1] if table == 'install'

        match = TOP_LEVEL_LINKER.match(line) unless table
        match && (match[1] || match[2])
      end

      # Whether bunfig.toml sets the install table with a dotted key or inline, before any table.
      def inline_install?
        bunfig_lines.take_while { !it.start_with?('[') }.any? { it.match?(INLINE_INSTALL) }
      end

      # A TOML comment: a # outside a basic ("…", with escapes) or literal ('…') string.
      COMMENT = /\A((?:[^#"']|"(?:[^"\\]|\\.)*"|'[^']*')*)#.*/

      # bunfig.toml's lines without comments or blank lines; none when there is no bunfig.toml.
      def bunfig_lines
        path = File.join(@root, 'bunfig.toml')
        return [] unless File.exist?(path)

        File.readlines(path).map { it.sub(COMMENT, '\\1').strip }.reject(&:empty?)
      end

      # A Rails app inside an enclosing JS workspace is out of v1: its contexts would belong to
      # the enclosing workspace's install, not the app's.
      def check_not_nested!
        root = File.expand_path(@root)
        dir = File.dirname(root)
        until dir == File.dirname(dir)
          if File.exist?(File.join(dir, 'pnpm-workspace.yaml')) || member?(dir, root)
            raise Error.new('PSM-E-NESTED-WORKSPACE', enclosing: dir)
          end

          dir = File.dirname(dir)
        end
      end

      # Whether the package.json in `dir` lists `root` among its workspaces. Bun installs an app
      # its patterns do not match as a project of its own (probed on Bun 1.4.2). `*` crosses `/`
      # here, so at worst an app that is not a member is refused.
      def member?(dir, root)
        path = File.join(dir, 'package.json')
        package = File.exist?(path) && ContextMap.read_json(path)
        return false unless package.is_a?(Hash)

        workspaces = package['workspaces']
        patterns = Array(workspaces.is_a?(Hash) ? workspaces['packages'] : workspaces).grep(String)
        excluded, included = patterns.map { it.delete_prefix('./').chomp('/') }
                                     .partition { it.start_with?('!') }
        relative = root.delete_prefix("#{dir}/")
        included.any? { glob?(it, relative) } && excluded.none? { glob?(it[1..], relative) }
      rescue JSON::ParserError
        # Bun reads a trailing comma Ruby refuses: one that may declare workspaces may hold the app.
        AppPackage.unescape(File.read(path)).include?('"workspaces"')
      end

      # Whether Bun's glob `pattern` matches `path`. FNM_EXTGLOB for braces, which Bun reads; and
      # each `**/` either way, as Bun's also matches no directory, which Ruby's does not.
      def glob?(pattern, path) = globs(pattern).any? { File.fnmatch?(it, path, File::FNM_EXTGLOB) }

      # `pattern` with each of its `**/` kept or dropped.
      def globs(pattern)
        head, star, tail = pattern.partition('**/')
        return [pattern] if star.empty?

        globs(tail).flat_map { ["#{head}#{star}#{it}", "#{head}#{it}"] }
      end

      # An executable on PATH, honoring PATHEXT on Windows (so `pnpm.cmd` is found), or nil.
      def self.which(command)
        exts = ENV['PATHEXT'] ? ENV['PATHEXT'].split(';').map(&:downcase) : ['']
        ENV.fetch('PATH', '').split(File::PATH_SEPARATOR).each do |dir|
          exts.each do |ext|
            # Absolute: the manager is spawned with the project as its working directory.
            path = File.expand_path(File.join(dir, "#{command}#{ext}"))
            return path if File.file?(path) && File.executable?(path)
          end
        end
        nil
      end
    end
  end
end
