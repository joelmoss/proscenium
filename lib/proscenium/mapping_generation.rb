# frozen_string_literal: true

require_relative 'bundled_gems'
require_relative 'context_map'
require_relative 'stale_contexts'

module Proscenium
  # Which mapping generation a build uses (#154). A generation is the context map and the
  # staleness verdict, read once and kept, so every build sees one consistent view. In production
  # a generation lasts the process: restart after a deploy. In development and test, `refresh`
  # looks at most once a second for a change to the files the map is built from, and starts a new
  # generation when one changed, such as `proscenium install` finishing.
  #
  # Gemfile.lock is watched, but a gem added or upgraded still needs a restart: Bundler loads the
  # bundle once per process.
  module MappingGeneration
    WATCHED = ['Gemfile.lock', 'proscenium.json', 'package.json', 'pnpm-workspace.yaml', '.npmrc',
               'bunfig.toml', ContextMap::INSTALLING].freeze
    EVERY = 1.0
    LOCK = Mutex.new

    module_function

    # The current generation number, starting a new one first if a watched file changed and the
    # last look was at least `every` seconds ago. Returns [number, whether it just changed].
    def refresh(root, every: EVERY)
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      LOCK.synchronize do
        @looked ||= {}
        @number ||= 0
        at, before = @looked[root]
        return [@number, false] if at && now - at < every

        after = signature(root)
        @looked[root] = [now, after]
        return [@number, false] if before.nil? || before == after

        ContextMap.reset!
        StaleContexts.reset!
        [@number += 1, true]
      end
    end

    # The modification time of every file the map is built from, by path, nil for a missing one.
    def signature(root)
      files = WATCHED.map { File.join(root, it) } +
              Dir.glob(File.join(root, ContextMap::CONTEXTS, '*', 'package.json')) +
              manifests(root)
      files.sort.to_h { [it, File.exist?(it) ? File.mtime(it).to_f : nil] }
    end

    # Each participating gem's package.json: editing a path gem's manifest makes its context stale.
    def manifests(root)
      BundledGems.participating(BundledGems.installed_specs, overrides: BundledGems.overrides(root))
                 .values.filter_map { BundledGems.manifest_root(it) }
                 .map { File.join(it, 'package.json') }
    rescue BundledGems::ConfigError
      []
    end

    def reset! = LOCK.synchronize { @looked = {} }
  end
end
