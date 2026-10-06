# frozen_string_literal: true

require 'json'
require_relative 'bundled_gems'
require_relative 'context_map'
require_relative 'dependency_context'
require_relative 'cli/contexts'
require_relative 'cli/error'
require_relative 'cli/verify'

module Proscenium
  # Whether an adopted app's committed gem dependency contexts are what its bundle calls for
  # (#154). A stale context resolves a gem's imports against the wrong dependency graph, so the
  # engine refuses to build until `proscenium install` brings them up to date. Built from
  # committed files and Bundler only; it loads nothing the `proscenium` CLI may not.
  module StaleContexts
    COMMAND = 'Run `bundle exec proscenium install` and commit .proscenium/packages.'
    EDITED = 'its dependency context was edited by hand'
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
      registrar = ContextMap.registrar(root)
      return [] unless registrar

      # Only the registration in use: a Bun app does not read a pnpm-workspace.yaml left over.
      unparsable = unparsable_workspace(root) if registrar == 'pnpm-workspace.yaml'
      return [unparsable] if unparsable

      participating = BundledGems.participating(specs, overrides: BundledGems.overrides(root))
      contexts = CLI::Contexts.new(root, participating)
      committed = CLI::Contexts.committed(root)
      found = contexts.problems.map { |code, args| CLI::Error.new(code, **args).message }
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

      ContextMap.yaml_packages(ContextMap.utf8(File.read(path)).delete_prefix(ContextMap::BOM))
      nil
    rescue Psych::SyntaxError => e
      "pnpm-workspace.yaml: it is not valid YAML (#{e.problem} at line #{e.line})"
    end

    # A peer meant to be shared that the gem and the app reach as two copies, as an app-only
    # `pnpm update react` can leave it: install checks this too, and the engine repeats it for each
    # generation.
    def split_peers(root, gems)
      pnpm = ContextMap.registers?(root, 'pnpm-workspace.yaml')
      CLI::Verify.new(root, Struct.new(:name).new(pnpm ? 'pnpm' : 'bun'), gems).check_peers
      []
    rescue CLI::Error => e
      [e.message]
    end

    # The committed context is projected again from the fields it holds, not taken on trust: a
    # hand edit that kept the reported hash would build against a graph no install produced.
    def compare(context, path)
      return "its dependency context hasn't been written yet" unless path && File.exist?(path)

      committed = ContextMap.read_json(path)
      unless committed.is_a?(Hash) && committed['proscenium'].is_a?(Hash)
        return 'its dependency context is not valid JSON'
      end
      if committed['proscenium']['projection'] != DependencyContext::PROJECTION
        return 'its dependency context was written by a different version of Proscenium'
      end

      # Parsed, so reformatting is not an edit; whole, so its name and the other generated fields
      # count as well as its hash.
      edited = DependencyContext.project(context.gem, committed) != committed
      return EDITED if edited
      return if committed == JSON.parse(context.json)

      'its NPM dependencies changed since its dependency context was written'
    rescue JSON::ParserError
      'its dependency context is not valid JSON'
    end

    # The build error for the app at `root`, or nil when its contexts are current. Read once per
    # mapping generation, as ContextMap.config is.
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
