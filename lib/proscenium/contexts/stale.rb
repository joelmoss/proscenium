# frozen_string_literal: true

require 'json'
require_relative '../app_package'
require_relative '../bundled_gems'
require_relative 'map'
require_relative 'projection'
require_relative 'plan'
require_relative 'messages'

module Proscenium
  module Contexts
    # Whether an adopted app's committed gem dependency contexts are what its bundle calls for
    # (#154). A stale context resolves a gem's imports against the wrong dependency graph, so the
    # engine refuses to build until `proscenium install` brings them up to date. Built from
    # committed files and Bundler only. The engine and the CLI both load it, so it loads nothing
    # the CLI may not, and nothing of cli/ (both directions are pinned by
    # test/cli/load_isolation_test.rb).
    module Stale
      COMMAND = 'Run `bundle exec proscenium install` and commit .proscenium/packages.'
      # Why a committed context is not the one install would write, by its `drift`. The engine,
      # `install --frozen` and `inspect` all classify a context with `drift`, so they name one
      # cause.
      REASONS = {
        missing: "its dependency context hasn't been written yet",
        invalid: 'its dependency context is not valid JSON',
        projection: 'its dependency context was written by a different version of Proscenium',
        edited: 'its dependency context was edited by hand',
        changed: 'its NPM dependencies changed since its dependency context was written'
      }.freeze
      ORPHAN = '%<gem>s: its dependency context is left over, as the gem is no longer in the ' \
               'bundle or no longer opted in'

      module_function

      # One line for each way the committed contexts differ from the bundle; empty when current, or
      # before the app adopts. A context is stale when a participating gem has none, when its gem
      # left Gemfile.lock or stopped participating, when its projection hash is not the gem's
      # current one, or when that hash is not the one its own fields produce (a hand edit). A
      # locked gem that is not installed (a group BUNDLE_WITHOUT excludes) keeps its context as
      # committed.
      def problems(root, specs = BundledGems.installed_specs, locked = BundledGems.locked_names)
        registrar = Map.registrar(root)
        return [] unless registrar

        # Only the registration in use: a Bun app does not read a pnpm-workspace.yaml left over.
        unparsable = unparsable_workspace(root) if registrar == 'pnpm-workspace.yaml'
        return [unparsable] if unparsable

        participating = BundledGems.participating(specs, overrides: BundledGems.overrides(root))
        contexts = Plan.new(root, participating)
        committed = Plan.committed(root)
        found = contexts.problems.map { |code, args| Messages.message(code, **args) }
        contexts.contexts.each_value do |context|
          problem = compare(context, committed[context.gem])
          found << "#{context.gem}: #{problem}" if problem
        end
        excluded = (locked || []) - specs.map(&:name)
        orphans = committed.keys - participating.keys - excluded
        found + orphans.map { format(ORPHAN, gem: it) } +
          split_peers(root, contexts.contexts.keys & committed.keys)
      rescue BundledGems::ConfigError => e
        [e.message]
      end

      # An app counts as adopted when a pnpm-workspace.yaml it cannot parse names the contexts, so
      # the engine never silently switches them off; it refuses until the file parses. Not
      # package.json: Bun reads JSON that Ruby refuses, such as a trailing comma.
      def unparsable_workspace(root)
        path = File.join(root, 'pnpm-workspace.yaml')
        return unless File.exist?(path)

        Map.yaml_packages(Map.utf8(File.read(path)).delete_prefix(Map::BOM))
        nil
      rescue Psych::SyntaxError => e
        "pnpm-workspace.yaml: it is not valid YAML (#{e.problem} at line #{e.line})"
      end

      # A peer meant to be shared that the gem and the app reach as two copies, as an app-only
      # `pnpm update react` can leave it: install checks this too, and the engine repeats it for
      # each generation.
      def split_peers(root, gems)
        gem, package = peer_split(root, gems)
        gem ? [Messages.message('PSM-E-PEER-SPLIT', gem:, package:)] : []
      end

      # The first `[gem, package]` where a peer a context declares, that the app also depends on,
      # resolves from the context and from the app to two different real directories; nil when
      # every one is a single copy. A context that is missing or not valid JSON has no peers to
      # check: `problems` and `install --frozen` report it themselves.
      def peer_split(root, gems)
        app = app_dependencies(root)
        gems.each do |gem|
          dir = File.join(root, Map::CONTEXTS, gem)
          (peers(dir).keys & app).each do |name|
            from_gem = real_dependency_dir(root, dir, name)
            from_app = real_dependency_dir(root, root, name)
            return [gem, name] unless from_gem.nil? || from_app.nil? || from_gem == from_app
          end
        end
        nil
      end

      def peers(dir)
        context = Map.read_json(File.join(dir, 'package.json'))
        peers = context['peerDependencies'] if context.is_a?(Hash)
        peers.is_a?(Hash) ? peers : {}
      rescue Errno::ENOENT, JSON::ParserError
        {}
      end

      def app_dependencies(root)
        package = Map.read_json(File.join(root, 'package.json'))
        return [] unless package.is_a?(Hash)

        AppPackage::DEPENDENCY_FIELDS.flat_map { package[it].is_a?(Hash) ? package[it].keys : [] }
      rescue Errno::ENOENT, JSON::ParserError
        []
      end

      # The real directory `name` resolves to from `dir`, walking up node_modules as Node does,
      # but no higher than the app at `root`.
      def real_dependency_dir(root, dir, name)
        current = dir
        loop do
          candidate = File.join(current, 'node_modules', name)
          return File.realpath(candidate) if File.exist?(candidate)
          return nil if current == root || current == File.dirname(current)

          current = File.dirname(current)
        end
      end

      # Why the engine refuses the committed context at `path`, or nil when it builds with it.
      def compare(context, path) = REASONS[drift(context, path)]

      # How the committed context at `path` differs from `context`, as a key of REASONS, or nil
      # when it holds the same JSON. It is projected again from the fields it holds, not taken on
      # trust: a hand edit that kept the reported hash would build against a graph no install
      # produced.
      def drift(context, path)
        return :missing unless path && File.exist?(path)

        committed = Map.read_json(path)
        return :invalid unless committed.is_a?(Hash) && committed['proscenium'].is_a?(Hash)
        return :projection if committed['proscenium']['projection'] != Projection::PROJECTION

        # Parsed, so reformatting is not an edit; whole, so its name and the other generated fields
        # count as well as its hash.
        return :edited if Projection.project(context.gem, committed) != committed

        :changed unless committed == JSON.parse(context.json)
      rescue JSON::ParserError
        :invalid
      end

      # The build error for the app at `root`, or nil when its contexts are current. Read once per
      # mapping generation, as Map.config is.
      def message(root, generation = 0)
        @message ||= {}
        key = [root, generation]
        return @message[key] if @message.key?(key)

        found = problems(root)
        @message[key] = if found.any?
                          "Gem dependency contexts are out of date:\n" \
                            "#{found.map { "  - #{it}" }.join("\n")}\n#{COMMAND}"
                        end
      end

      def reset! = @message = {}
    end
  end
end
