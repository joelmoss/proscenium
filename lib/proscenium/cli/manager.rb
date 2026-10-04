# frozen_string_literal: true

require 'json'
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
        if !requested && lockfiles.size > 1
          raise Error.new('PSM-E-MANAGER-CONFLICT', signals: lockfiles.join(' and '))
        end
        if requested && lockfiles.any? && !lockfiles.include?(requested)
          raise Error.new('PSM-E-MANAGER-CONFLICT',
                          signals: ([requested] + lockfiles).join(' and '))
        end
        raise Error, 'PSM-E-BUN-LOCKB' if !name && File.exist?(File.join(root, 'bun.lockb'))
        raise Error, 'PSM-E-NO-MANAGER' unless name
        raise Error.new('PSM-E-UNSUPPORTED-MANAGER', manager: name) unless SUPPORTED.include?(name)

        new(name, root)
      end

      # The manager named by package.json's `packageManager` (`pnpm@10.33.1+sha512...`), or nil.
      def self.from_package_manager(root)
        path = File.join(root, 'package.json')
        return nil unless File.exist?(path)

        field = JSON.parse(File.read(path))['packageManager']
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
        @version = pinned_version || probed_version
        return self if line

        raise Error, 'PSM-E-EXPERIMENTAL-FROZEN' if experimental && frozen
        unless experimental
          raise Error.new('PSM-E-MANAGER-VERSION', manager: @name, version: @version,
                                                   supported: supported_ranges)
        end

        self
      end

      # The capability table's line for the installed version, or nil.
      def line
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

      # Bun registers contexts only in a project that has chosen its linker and its trusted
      # dependencies explicitly: without them, registering a workspace can switch the app to
      # another linker, and Bun's default trusted list would run scripts of packages a gem
      # introduces.
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
        field = File.exist?(path) && JSON.parse(File.read(path))['packageManager']
        return unless field.is_a?(String)

        name, version = field.split('+').first.split('@', 2)
        version if name == @name && version
      rescue JSON::ParserError
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

      # A missing Bun linker is written by registration (BunLinker), so only `frozen`, which writes
      # nothing, refuses it; an unknown one is always refused.
      def check_project!(frozen: false)
        check_not_nested!
        return self unless @name == 'bun'

        linker = bun_linker
        raise Error, 'PSM-E-BUN-LINKER' if linker ? !LINKERS.include?(linker) : frozen

        package = File.join(@root, 'package.json')
        trusted = File.exist?(package) && JSON.parse(File.read(package))['trustedDependencies']
        raise Error, 'PSM-E-BUN-TRUSTED' unless trusted.is_a?(Array)

        self
      end

      # The `linker` set in bunfig.toml's `[install]` table, or nil.
      def bun_linker
        path = File.join(@root, 'bunfig.toml')
        return nil unless File.exist?(path)

        table = nil
        File.foreach(path) do |raw|
          line = raw.sub(/#.*/, '').strip
          next if line.empty?

          if (header = line[/\A\[([^\]]+)\]\z/, 1])
            table = header.strip
          elsif table == 'install' && (value = line[/\Alinker\s*=\s*["']([^"']*)["']\z/, 1])
            return value
          end
        end
        nil
      end

      # A Rails app inside an enclosing JS workspace is out of v1: its contexts would belong to
      # the enclosing workspace's install, not the app's.
      def check_not_nested!
        dir = File.dirname(File.expand_path(@root))
        until dir == File.dirname(dir)
          if File.exist?(File.join(dir,
                                   'pnpm-workspace.yaml')) || workspaces?(File.join(dir,
                                                                                    'package.json'))
            raise Error.new('PSM-E-NESTED-WORKSPACE', enclosing: dir)
          end

          dir = File.dirname(dir)
        end
      end

      def workspaces?(path)
        File.exist?(path) && JSON.parse(File.read(path)).key?('workspaces')
      rescue JSON::ParserError
        false
      end

      # An executable on PATH, honoring PATHEXT on Windows (so `pnpm.cmd` is found), or nil.
      def self.which(command)
        exts = ENV['PATHEXT'] ? ENV['PATHEXT'].split(';').map(&:downcase) : ['']
        ENV.fetch('PATH', '').split(File::PATH_SEPARATOR).each do |dir|
          exts.each do |ext|
            path = File.join(dir, "#{command}#{ext}")
            return path if File.file?(path) && File.executable?(path)
          end
        end
        nil
      end
    end
  end
end
