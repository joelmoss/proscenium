# frozen_string_literal: true

require 'fileutils'
require 'bundler'
require_relative '../bundled_gems'
require_relative '../dependency_context'
require_relative 'collisions'
require_relative 'contexts'
require_relative 'diff'
require_relative 'manager'
require_relative 'platform_variants'
require_relative 'project_lock'
require_relative 'registration'
require_relative 'runner'
require_relative 'verify'

module Proscenium
  module CLI
    # `proscenium install` and `install --frozen` (#154): the plan's installation algorithm.
    class Install
      LOCKFILES = { 'pnpm' => 'pnpm-lock.yaml', 'bun' => 'bun.lock' }.freeze

      # Options: frozen, production, offline, manager (requested), experimental, js_args.
      def initialize(root, reporter, **options)
        @root = root
        @reporter = reporter
        @options = options
      end

      def call
        @timings = {}
        if defined?(PROSCENIUM_STARTED)
          @timings[:load] = ms(Process.clock_gettime(Process::CLOCK_MONOTONIC) - PROSCENIUM_STARTED)
        end
        timed(:manager_check) do
          @manager = Manager.select(@root, requested: @options[:manager])
          @manager.check_version!(experimental: @options[:experimental], frozen: frozen?)
          @manager.check_project!(frozen: frozen?)
        end
        if (warning = @manager.end_of_life_warning)
          @reporter.warning(warning, phase: 'manager')
        end
        read_bundle
        frozen? ? check_frozen : install
        0
      end

      # The gems whose contexts declare a package the manager's failure output names, as
      # [gem, package] pairs: an age-gate refusal or a failed fetch names only the package.
      def self.blame(contexts, output)
        return [] unless output.match?(/ERR_|error:/i)

        contexts.flat_map do |gem, json|
          context = JSON.parse(json)
          Rules::DEPENDENCY_FIELDS.flat_map { (context[it] || {}).keys }
                                  .reject { it.start_with?('@rubygems/') }
                                  .select { output.match?(named(it)) }
                                  .map { [gem, it] }
        end
      end

      # `name` as a whole package name, not a part of another.
      def self.named(name) = %r{(?<![\w@/.-])#{Regexp.escape(name)}(?![\w/-])}

      private

      def frozen? = @options[:frozen]

      # Milliseconds each phase took, reported with the result so an install's cost can be split
      # between Proscenium and the manager (C40).
      def timed(phase)
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        yield
      ensure
        @timings[phase] = ms(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started)
      end

      def ms(seconds) = (seconds * 1000).round

      def read_bundle
        overrides = BundledGems.overrides(@root)
        specs = timed(:bundle) { BundledGems.installed_specs }
        @excluded = BundledGems.excluded_names(specs)
        @contexts = timed(:projection) do
          Contexts.new(@root, BundledGems.participating(specs, overrides:))
        end
        @committed = Contexts.committed(@root)
        check_owned_directory
        report_problems
        check_platform_variants(specs)
        check_collisions
      rescue BundledGems::ConfigError => e
        raise Error.new('PSM-E-CONFIG', detail: e.message)
      end

      def report_problems
        @contexts.warnings.each do |code, args|
          @reporter.warning(Error.new(code, **args), phase: 'validate')
        end
        return if @contexts.ok?

        @contexts.problems.each do |code, args|
          @reporter.error(Error.new(code, **args), phase: 'validate', manager: @manager.name)
        end
        raise Error.new('PSM-E-PROBLEMS', count: @contexts.problems.size)
      end

      # `.proscenium/packages/` is Proscenium's: every entry is a generated context. A package.json
      # there without the generated `proscenium` block is someone's own package, and install
      # refuses rather than delete it as an orphan.
      def check_owned_directory
        check_owned_links
        foreign = @committed.select do |_, path|
          next false unless File.exist?(path)

          package = JSON.parse(File.read(path))
          !package.is_a?(Hash) || !package.key?('proscenium')
        rescue JSON::ParserError
          true
        end
        return if foreign.empty?

        raise Error.new('PSM-E-OWNED-DIR', entries: foreign.keys.join(', '))
      end

      # Everything install writes is under .proscenium/ (C29). A link anywhere on the way, or in
      # place of a context, would send those writes outside the app.
      def check_owned_links
        owned = ['.proscenium', Contexts::DIR] + @committed.flat_map do |gem, path|
          [File.join(Contexts::DIR, gem), relative(path)]
        end
        links = owned.select { File.symlink?(File.join(@root, it)) }
        raise Error.new('PSM-E-OWNED-LINK', paths: links.join(', ')) if links.any?
      end

      def check_platform_variants(specs)
        found = PlatformVariants.differences(Bundler.app_cache.to_s, specs)
        return if found.empty?

        raise Error.new('PSM-E-PLATFORM-VARIANT',
                        variants: found.map { |gem, file| "#{gem} (#{file})" }.join(', '))
      end

      def check_collisions
        found = Collisions.find(@root, @manager.name, @contexts.contexts.keys)
        return if found.empty?

        raise Error.new('PSM-E-COLLISION', count: found.size,
                                           list: found.map { "  - #{it}" }.join("\n"))
      end

      # Committed contexts no participating gem owns. A locked gem that is not installed (another
      # group or platform) keeps its context: the production rule trusts it.
      def orphans = @committed.keys - @contexts.contexts.keys - @excluded

      def changed
        @contexts.contexts.values.reject do |context|
          path = @committed[context.gem]
          path && File.exist?(path) && File.read(path) == context.json
        end
      end

      def check_frozen
        drift = []
        registered = Registration.registered?(@root, @manager.name)
        drift << 'the gem contexts are not registered' unless registered
        drift << "#{lockfile} is missing" unless File.exist?(File.join(@root, lockfile))
        changed.each { drift << describe_change(it) }
        orphans.each { drift << "#{it}: its context belongs to no participating gem" }
        unless drift.empty?
          list = drift.map { "  - #{it}" }.join("\n")
          raise Error.new('PSM-E-DRIFT', count: drift.size, list:)
        end

        timed(:manager) { run_manager }
        timed(:verify) { Verify.new(@root, @manager, @contexts.contexts.keys).call }
        lines = ["Everything is up to date for #{@contexts.contexts.size} gems.", *kept]
        @reporter.info(lines.join("\n"), event: 'frozen', timings: @timings)
      end

      # A line for each committed context kept for a gem that is not installed.
      def kept
        (@excluded & @committed.keys).map { "  #{it}: not installed, its committed context kept" }
      end

      def describe_change(context)
        path = @committed[context.gem]
        return "#{context.gem}: no context is committed" unless path && File.exist?(path)

        before = File.read(path)
        diff = Diff.unified(relative(path), before, context.json)
        committed = JSON.parse(before)['proscenium'] || {}
        current = JSON.parse(context.json)['proscenium']
        cause = if committed['projection'] != current['projection']
                  "context projection changed from #{committed['projection']} to " \
                    "#{current['projection']}; run bundle exec proscenium install and commit " \
                    '.proscenium/packages'
                elsif committed['projectionSha256'] == current['projectionSha256']
                  'its context was edited by hand'
                else
                  'its context is out of date'
                end
        "#{context.gem}: #{cause}\n#{diff}"
      rescue JSON::ParserError
        "#{context.gem}: its context is not valid JSON"
      end

      def install
        lock = ProjectLock.new(@root)
        lock.synchronize('proscenium install') do
          @reporter.info('Finishing an interrupted install.', event: 'recover') if lock.interrupted?
          lock.mark!
          @written = register + write_contexts + remove_orphans
          timed(:manager) { run_manager(lock) }
          timed(:verify) { Verify.new(@root, @manager, @contexts.contexts.keys).call }
          lock.unmark!
        end
        summarize
      end

      # The one-time registration, printed as a diff before it is written.
      def register
        Registration.edits(@root, @manager.name).map do |path, before, after|
          @reporter.info(Diff.unified(relative(path), before, after), event: 'registration',
                                                                      file: relative(path))
          File.write(path, after)
          relative(path)
        end
      end

      # Each changed context, written atomically; an unchanged one is left alone, so its native
      # links survive.
      def write_contexts
        changed.map do |context|
          dir = File.join(@root, Contexts::DIR, context.gem)
          FileUtils.mkdir_p(dir)
          path = File.join(dir, 'package.json')
          File.write("#{path}.tmp", context.json)
          File.rename("#{path}.tmp", path)
          relative(path)
        end
      end

      def remove_orphans
        orphans.map do |gem|
          FileUtils.rm_rf(File.join(@root, Contexts::DIR, gem))
          "#{Contexts::DIR}/#{gem} (removed)"
        end
      end

      def run_manager(lock = nil)
        Runner.run(@manager.executable, manager_args, root: @root, lock_io: lock&.io,
                                                      on_spawn: lock&.method(:manager_started),
                                                      manager: @manager.name)
      rescue Error => e
        raise unless e.code == 'PSM-E-NATIVE'

        blamed = self.class.blame(@contexts.contexts.transform_values(&:json), e.output.to_s)
        raise if blamed.empty?

        involved = blamed.map { |gem, package| "#{package}, which #{gem} brings in" }.join('; ')
        error = Error.new('PSM-E-NATIVE', command: "#{@manager.name} #{manager_args.join(' ')}",
                                          status: e.details[:exitStatus], details: e.details,
                                          escape: "It involves #{involved}.")
        raise error
      ensure
        lock&.manager_finished
      end

      def manager_args
        args = ['install']
        args << '--frozen-lockfile' if frozen?
        args << (@manager.name == 'bun' ? '--production' : '--prod') if @options[:production]
        args << '--offline' if @options[:offline]
        # A gem only in an excluded group has no source to read; its context is trusted and its
        # dependencies left out of a production install.
        if @options[:production]
          (@excluded & @committed.keys).each do |gem|
            args << "--filter=!#{DependencyContext.name_for(gem)}"
          end
        end
        args + Array(@options[:js_args])
      end

      def lockfile = LOCKFILES.fetch(@manager.name)

      def relative(path) = path.delete_prefix("#{@root}/")

      def summarize
        contexts = @contexts.contexts.values
        lines = ["Installed JavaScript dependencies for #{contexts.size} gems with " \
                 "#{@manager.name} #{@manager.version}."]
        contexts.each do |context|
          count = JSON.parse(context.json).values_at('dependencies', 'peerDependencies',
                                                     'optionalDependencies').compact.sum(&:size)
          lines << "  #{context.gem}: #{count} dependencies"
        end
        introduced = contexts.flat_map(&:git_and_url)
        if introduced.any?
          lines << "Git and URL dependencies gems introduced: #{introduced.join(', ')}"
        end
        lines.concat(kept)
        commit = @written + [lockfile]
        lines << "Commit: #{commit.uniq.join(', ')}"
        @reporter.info(lines.join("\n"), event: 'installed', manager: @manager.name,
                                         gems: contexts.map(&:gem), commit: commit.uniq,
                                         timings: @timings)
      end
    end
  end
end
