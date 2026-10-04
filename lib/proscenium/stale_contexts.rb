# frozen_string_literal: true

require 'json'
require_relative 'bundled_gems'
require_relative 'context_map'
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

    module_function

    # One line for each way the committed contexts differ from the bundle; empty when current, or
    # before the app adopts. A context is stale when a participating gem has none, when its gem
    # left Gemfile.lock or stopped participating, or when its projection hash is not the gem's
    # current one. A locked gem that is not installed (a group BUNDLE_WITHOUT excludes) keeps
    # its context as committed.
    def problems(root, specs = BundledGems.installed_specs, locked = BundledGems.locked_names)
      return [] unless ContextMap.adopted?(root)

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
      found + orphans.map { "#{it}: its context belongs to no participating gem" } +
        split_peers(root, contexts.contexts.keys & committed.keys)
    rescue BundledGems::ConfigError => e
      [e.message]
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

    def compare(context, path)
      return 'it has no committed context' unless path && File.exist?(path)

      current = JSON.parse(context.json).dig('proscenium', 'projectionSha256')
      return if JSON.parse(File.read(path)).dig('proscenium', 'projectionSha256') == current

      'its JavaScript dependencies changed since its context was written'
    rescue JSON::ParserError
      'its committed context is not valid JSON'
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
