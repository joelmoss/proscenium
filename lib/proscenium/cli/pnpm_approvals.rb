# frozen_string_literal: true

require_relative '../context_map'
require_relative '../yaml_tree'

module Proscenium
  module CLI
    # The package names pnpm-workspace.yaml approves builds for (#154): allowBuilds' keys set to
    # true, a version dropped (`name@1.0.0`), and the older onlyBuiltDependencies. Read as pnpm
    # reads it, aliases and merge keys included, from the parse tree.
    module PnpmApprovals
      module_function

      # A pnpm setting from the environment: `PNPM_CONFIG_<KEY>`, which pnpm 11 and 12 read ahead
      # of `pnpm_config_<key>`, or nil.
      def env(key)
        ENV.fetch("PNPM_CONFIG_#{key.upcase}") { ENV.fetch("pnpm_config_#{key}", nil) }
      end

      # Whether pnpm runs every package's build: dangerouslyAllowAllBuilds, which pnpm 11 and 12
      # read from the environment, pnpm-workspace.yaml and pnpm's global config.yaml. Any of them
      # saying true is enough.
      def allow_all?(root)
        env = %w[PNPM_CONFIG_DANGEROUSLY_ALLOW_ALL_BUILDS pnpm_config_dangerously_allow_all_builds]
        return true if env.any? { ENV.fetch(it, nil) == 'true' }

        [File.join(root, 'pnpm-workspace.yaml'), global_config].any? do |path|
          setting?(path, 'dangerouslyAllowAllBuilds')
        end
      end

      # pnpm's global config.yaml: under $XDG_CONFIG_HOME/pnpm, else ~/Library/Preferences/pnpm on
      # macOS (both probed), ~/.config/pnpm on Linux and %LOCALAPPDATA%\pnpm\config on Windows
      # (as pnpm documents them).
      def global_config
        xdg = ENV.fetch('XDG_CONFIG_HOME', nil)
        return File.join(xdg, 'pnpm', 'config.yaml') if xdg
        if Gem.win_platform?
          return File.join(ENV.fetch('LOCALAPPDATA', Dir.home), 'pnpm', 'config', 'config.yaml')
        end

        dir = RUBY_PLATFORM.include?('darwin') ? 'Library/Preferences/pnpm' : '.config/pnpm'
        File.join(Dir.home, dir, 'config.yaml')
      end

      # Whether the YAML file at `path` sets `key` to true.
      def setting?(path, key)
        return false unless File.exist?(path)

        text = ContextMap.utf8(File.read(path)).delete_prefix(ContextMap::BOM)
        value, anchors = YamlTree.value(text, key)
        true?(YamlTree.node(value, anchors))
      rescue Psych::SyntaxError
        false
      end

      def names(root)
        path = File.join(root, 'pnpm-workspace.yaml')
        return [] unless File.exist?(path)

        text = ContextMap.utf8(File.read(path)).delete_prefix(ContextMap::BOM)
        allowed, anchors = YamlTree.value(text, 'allowBuilds')
        listed, = YamlTree.value(text, 'onlyBuiltDependencies')
        node = ->(given) { YamlTree.node(given, anchors) }
        names = approvals(allowed, node).select { |_, approved| approved }.keys
        listed = listed.is_a?(Psych::Nodes::Sequence) ? listed.children.map(&node) : []
        names += listed.grep(Psych::Nodes::Scalar).map(&:value)
        # The package name alone: an opaque locator (`foo@https://host/pkg@1.0.0`) approves `foo`.
        names.map { it.sub(/(?<=.)@.*\z/m, '') }.uniq
      rescue Psych::SyntaxError
        []
      end

      # Name => whether approved, for a mapping. A merge key (`<<`) brings in its mapping's, or
      # mappings', entries; the mapping's own keys override them, and an earlier merged mapping
      # overrides a later one, as YAML merges. A mapping already being merged is a cycle, which
      # ends there.
      def approvals(mapping, node, merging = [])
        return {} unless mapping.is_a?(Psych::Nodes::Mapping)
        return {} if merging.any? { it.equal?(mapping) }

        own = {}
        merged = {}
        mapping.children.each_slice(2) do |key, value|
          key = node.call(key)
          value = node.call(value)
          if scalar?(key, '<<')
            sources = value.is_a?(Psych::Nodes::Sequence) ? value.children.map(&node) : [value]
            sources.each { merged = approvals(it, node, [*merging, mapping]).merge(merged) }
          elsif scalar?(key)
            own[key.value] = true?(value)
          end
        end
        merged.merge(own)
      end

      # YAML's true in the core schema pnpm reads: `true`, `True` or `TRUE`, unquoted.
      def true?(node)
        node.is_a?(Psych::Nodes::Scalar) && !node.quoted && TRUE_VALUES.include?(node.value)
      end

      TRUE_VALUES = %w[true True TRUE].freeze

      def scalar?(node, value = nil)
        node.is_a?(Psych::Nodes::Scalar) && (value.nil? || node.value == value)
      end
    end
  end
end
