# frozen_string_literal: true

require 'json'
require_relative '../context_map'
require_relative 'manager'

module Proscenium
  module CLI
    # What install checks after the manager has run (#154): no gem context came from a registry,
    # the manager installed every context (Bun exits 0 when a workspace is missing, so this is
    # Proscenium's to check), and a peer meant to be shared is one copy.
    class Verify
      # A `packages:` key in pnpm-lock.yaml, and a `packages` entry in bun.lock, for a
      # `@rubygems/*` package that is not a link to its context. A pnpm key starting with `@` is
      # always quoted, and a Git one holds colons: `'@rubygems/hue@git+ssh://git@github.com/...':`.
      PNPM_REGISTRY = %r{^\s{2}'(@rubygems/[^@'\s]+)@(?!link:|workspace:)[^']*':\s*$}
      BUN_REGISTRY = %r{"(@rubygems/[^"]+)":\s*\["@rubygems/[^@"]+@(?!workspace:)}

      def initialize(root, manager, gems)
        @root = root
        @manager = manager
        @gems = gems
      end

      def call
        lock = File.read(File.join(@root, Manager::LOCKFILES.key(@manager.name)))
        check_registry(lock)
        check_workspaces(lock)
        check_peers
      end

      # A `@rubygems/*` package resolved from a registry, rather than linked to its context.
      # bun.lock is JSON with trailing commas, so both locks are scanned as text.
      def check_registry(lock)
        found = lock.scan(@manager.name == 'pnpm' ? PNPM_REGISTRY : BUN_REGISTRY).flatten
        return if found.empty?

        raise Error.new('PSM-E-REGISTRY-TARBALL', packages: found.uniq.join(', '))
      end

      def check_workspaces(lock)
        missing = @gems.reject do |gem|
          path = ".proscenium/packages/#{gem}"
          if @manager.name == 'pnpm'
            # An importer with no dependencies is written on one line: `  <path>: {}`.
            lock.match?(/^  #{Regexp.escape(path)}:(?: \{\})?$/)
          else
            lock.include?("\"#{path}\"")
          end
        end
        return if missing.empty?

        raise Error.new('PSM-E-WORKSPACE-MISSING', gems: missing.join(', '), manager: @manager.name)
      end

      # Each peer a context declares that the app also depends on must resolve, from the context
      # and from the app, to one real directory. A context that is missing or not valid JSON has
      # no peers to check; StaleContexts and `install --frozen` report it themselves.
      def check_peers
        app = app_dependencies
        @gems.each do |gem|
          dir = File.join(@root, '.proscenium', 'packages', gem)
          (peers(dir).keys & app).each do |name|
            from_gem = resolve(dir, name)
            from_app = resolve(@root, name)
            next if from_gem.nil? || from_app.nil? || from_gem == from_app

            raise Error.new('PSM-E-PEER-SPLIT', gem:, package: name, manager: @manager.name)
          end
        end
      end

      def peers(dir)
        context = ContextMap.read_json(File.join(dir, 'package.json'))
        peers = context['peerDependencies'] if context.is_a?(Hash)
        peers.is_a?(Hash) ? peers : {}
      rescue Errno::ENOENT, JSON::ParserError
        {}
      end

      def app_dependencies
        package = ContextMap.read_json(File.join(@root, 'package.json'))
        return [] unless package.is_a?(Hash)

        # Peers too: pnpm installs the app's own peers at the root.
        %w[dependencies devDependencies optionalDependencies peerDependencies].flat_map do |field|
          package[field].is_a?(Hash) ? package[field].keys : []
        end
      rescue Errno::ENOENT, JSON::ParserError
        []
      end

      # The real directory `name` resolves to from `dir`, walking up node_modules as Node does,
      # but no higher than the app.
      def resolve(dir, name)
        current = dir
        loop do
          candidate = File.join(current, 'node_modules', name)
          return File.realpath(candidate) if File.exist?(candidate)
          return nil if current == @root || current == File.dirname(current)

          current = File.dirname(current)
        end
      end
    end
  end
end
