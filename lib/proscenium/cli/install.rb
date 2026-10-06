# frozen_string_literal: true

require 'fileutils'
require 'bundler'
require_relative '../bundled_gems'
require_relative '../dependency_context'
require_relative '../stale_contexts'
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
      # What a context directory without its package.json may hold and still be install's to remove.
      OURS = %w[node_modules package.json.tmp .DS_Store].freeze

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

      def count(...) = Reporter.count(...)

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
        check_platform_variants(specs, overrides)
        check_trusted_sources
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
      # there without the generated `proscenium` block, or a folder with no package.json that holds
      # more than a node_modules, is someone else's, and install refuses rather than delete it as an
      # orphan.
      def check_owned_directory
        check_owned_links
        foreign = @committed.select do |gem, path|
          # Without a context, only an old context's node_modules, a write that never finished, or
          # macOS's .DS_Store is ours to remove; anything else, a .git included, is the user's.
          next (Dir.children(File.dirname(path)) - OURS).any? unless File.exist?(path)

          !generated?(gem, ContextMap.read_json(path))
        rescue JSON::ParserError
          true
        end
        entries = foreign.keys + strays
        return if entries.empty?

        raise Error.new('PSM-E-OWNED-DIR', entries: entries.join(', '))
      end

      # Whether `package` is a context install wrote for `gem`: its generated name, and a
      # `proscenium` block naming a projection. A `proscenium` key alone is not enough, or install
      # would remove someone else's package as an orphan.
      def generated?(gem, package)
        package.is_a?(Hash) && package['name'] == DependencyContext.name_for(gem) &&
          package.dig('proscenium', 'projection').is_a?(String)
      rescue TypeError
        false
      end

      # A file, or a link leading nowhere, where only context directories belong.
      def strays
        dir = File.join(@root, Contexts::DIR)
        return [] unless Dir.exist?(dir)

        Dir.children(dir).reject { File.directory?(File.join(dir, it)) } - OURS
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

      def check_platform_variants(specs, overrides)
        found = PlatformVariants.differences(Bundler.app_cache.to_s, specs, overrides:)
        return if found.empty?

        raise Error.new('PSM-E-PLATFORM-VARIANT',
                        variants: found.map { |gem, file| "#{gem} (#{file})" }.join(', '))
      end

      def check_trusted_sources
        manifests = @contexts.contexts.transform_values { JSON.parse(it.json) }
        # Bun's trust is read only when a gem reaches some package another way.
        return if Rules.substitutions(manifests).empty?

        found = Rules.trusted_substitutions(@manager.trusted_names, manifests)
        return if found.empty?

        raise Error.new('PSM-E-TRUSTED-SOURCE', list: found.map { "  - #{it}" }.join("\n"))
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
        # The lock, not the marker: a frozen install writes nothing of Proscenium's, but its manager
        # writes node_modules, so it must not run alongside another install. Drift is read and the
        # tree verified under it too, so another install cannot change what is being compared.
        ProjectLock.new(@root).synchronize('proscenium install --frozen') do |lock|
          check_drift
          timed(:manager) { run_manager(lock) }
          timed(:verify) { Verify.new(@root, @manager, @contexts.contexts.keys).call }
        end
        headline = "Everything is up to date for #{count(@contexts.contexts.size, 'gem')}."
        lines = [@reporter.paint(headline, :bold, :green), *kept]
        lines.unshift('') unless @reporter.json?
        @reporter.info(lines.join("\n"), event: 'frozen', timings: @timings)
      end

      def check_drift
        @committed = Contexts.committed(@root)
        drift = []
        registered = Registration.registered?(@root, @manager.name)
        drift << 'the gem contexts are not registered' unless registered
        drift << "#{lockfile} is missing" unless File.exist?(File.join(@root, lockfile))
        changed.each { drift << describe_change(it) }
        orphans.each { drift << format(StaleContexts::ORPHAN, gem: it) }
        return if drift.empty?

        list = drift.map { "  - #{it}" }.join("\n")
        raise Error.new('PSM-E-DRIFT', count: drift.size, list:)
      end

      # A line for each committed context kept for a gem that is not installed.
      def kept
        (@excluded & @committed.keys).map do |gem|
          "  #{gem} is not installed here, so its committed dependency context was kept as it is."
        end
      end

      def describe_change(context)
        path = @committed[context.gem]
        unless path && File.exist?(path)
          return "#{context.gem}: its dependency context hasn't been written yet"
        end

        before = File.read(path)
        diff = Diff.unified(relative(path), before, context.json)
        committed = JSON.parse(before)['proscenium'] || {}
        current = JSON.parse(context.json)['proscenium']
        cause = if committed['projection'] != current['projection']
                  'its dependency context was written by a different version of Proscenium'
                elsif committed['projectionSha256'] == current['projectionSha256']
                  'its dependency context was edited by hand'
                else
                  'its NPM dependencies changed since its dependency context was written'
                end
        "#{context.gem}: #{cause}\n#{diff}"
      rescue JSON::ParserError
        "#{context.gem}: its dependency context is not valid JSON"
      end

      def install
        lock = ProjectLock.new(@root)
        lock.synchronize('proscenium install') do
          if lock.interrupted?
            @reporter.info('Finishing an install that was stopped before it finished.',
                           event: 'recover')
          end
          # Computed before the marker: a registration it refuses has changed nothing, and must not
          # leave the engine refusing every build.
          edits = Registration.edits(@root, @manager.name)
          lock.mark!
          @written = register(edits) + write_contexts + remove_orphans
          timed(:manager) { run_manager(lock) }
          timed(:verify) { Verify.new(@root, @manager, @contexts.contexts.keys).call }
          lock.unmark!
        end
        summarize
      end

      # The one-time registration, printed as a diff before it is written.
      def register(edits)
        edits.map do |path, before, after|
          diff = Diff.unified(relative(path), before, after)
          message = if @reporter.json? then diff
                    else "Updating #{relative(path)}:\n#{@reporter.paint_diff(diff)}"
                    end
          @reporter.info(message, event: 'registration', file: relative(path))
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
          ProjectLock.write("#{path}.tmp", context.json)
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
        unless @reporter.json?
          @reporter.info(@reporter.paint("Running #{@manager.name} #{manager_args.join(' ')}...",
                                         :dim))
        end
        Runner.run(@manager.executable, manager_args, root: @root,
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

      def lockfile = Manager::LOCKFILES.key(@manager.name)

      def relative(path) = path.delete_prefix("#{@root}/")

      def summarize
        contexts = @contexts.contexts.values
        headline = "Installed NPM dependencies for #{count(contexts.size, 'gem')} with " \
                   "#{@manager.name} #{@manager.version}."
        width = contexts.map { it.gem.size }.max.to_i
        lines = [@reporter.paint(headline, :bold, :green)]
        contexts.each do |context|
          total = JSON.parse(context.json).values_at('dependencies', 'peerDependencies',
                                                     'optionalDependencies').compact.sum(&:size)
          lines << "  #{context.gem.ljust(width)}  #{count(total, 'dependency', 'dependencies')}"
        end
        introduced = contexts.flat_map(&:git_and_url)
        if introduced.any?
          lines << '' << 'Gems bring in these Git and URL dependencies:'
          lines.concat(introduced.map { "  #{it}" })
        end
        lines.concat(kept)
        commit = (@written + [lockfile]).uniq
        lines << '' << @reporter.paint('Commit these files:', :bold)
        lines.concat(commit.map { "  #{it}" })
        lines.unshift('') unless @reporter.json?
        @reporter.info(lines.join("\n"), event: 'installed', manager: @manager.name,
                                         gems: contexts.map(&:gem), commit:, timings: @timings)
      end
    end
  end
end
