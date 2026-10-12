# frozen_string_literal: true

require_relative '../contexts/map'
require_relative '../contexts/stale'
require_relative 'manager'

module Proscenium
  module CLI
    # What install checks after the manager has run (#154): no gem context came from a registry,
    # the manager installed every context (Bun exits 0 when a workspace is missing, so this is
    # Proscenium's to check), and a peer meant to be shared is one copy.
    class Verify
      # A `packages:` key in pnpm-lock.yaml, and a `packages` entry in bun.lock, for a
      # `@rubygems/*` package that is not a link to its context. A pnpm key starting with `@` is
      # always quoted, and a Git one holds colons:
      # `'@rubygems/ui-gem@git+ssh://git@github.com/...':`.
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
          path = "#{Contexts::Map::CONTEXTS}/#{gem}"
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
      # and from the app, to one real directory. The rule is the engine's too, so it lives with
      # Contexts::Stale.
      def check_peers
        gem, package = Contexts::Stale.peer_split(@root, @gems)
        raise Error.new('PSM-E-PEER-SPLIT', gem:, package:) if gem
      end
    end
  end
end
