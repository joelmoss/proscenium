# frozen_string_literal: true

require 'yaml'

module Proscenium
  # YAML read from Psych's parse tree, never built into Ruby objects (#154): no alias can make it
  # slow, and no tag or date can raise. Shared by the engine and the `proscenium` CLI, so it loads
  # nothing the CLI may not.
  module YamlTree
    module_function

    # The node a root mapping's last `key` holds, aliases resolved, and the document's anchors; nil
    # when the document is not a mapping or has no such key. A key the root inherits through a
    # merge key (`<<: *defaults`) counts, as pnpm reads it. Raises Psych::SyntaxError.
    def value(text, key)
      root = Psych.parse_stream(text).children.first&.root
      return unless root.is_a?(Psych::Nodes::Mapping)

      anchors = root.each.grep_v(Psych::Nodes::Alias).select(&:anchor).to_h { [it.anchor, it] }
      [lookup(root, key, anchors), anchors]
    end

    # `key`'s node in `mapping`: its own last one, else the first merged mapping's, following
    # merges until one is already being looked in.
    def lookup(mapping, key, anchors, merging = [])
      return unless mapping.is_a?(Psych::Nodes::Mapping) && merging.none? { it.equal?(mapping) }

      pairs = mapping.children.each_slice(2).map { |name, value| [node(name, anchors), value] }
      _, found = pairs.reverse_each.find { |name, _| scalar?(name, key) }
      return node(found, anchors) if found

      merges = pairs.filter_map { |name, value| node(value, anchors) if scalar?(name, '<<') }
      merges.each do |merged|
        sources = merged.is_a?(Psych::Nodes::Sequence) ? merged.children : [merged]
        sources.each do |source|
          inherited = lookup(node(source, anchors), key, anchors, [*merging, mapping])
          return inherited if inherited
        end
      end
      nil
    end

    def scalar?(node, value) = node.is_a?(Psych::Nodes::Scalar) && node.value == value

    # The node an alias names, or the node itself.
    def node(node, anchors) = node.is_a?(Psych::Nodes::Alias) ? anchors[node.anchor] : node
  end
end
