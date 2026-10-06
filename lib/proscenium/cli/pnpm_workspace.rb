# frozen_string_literal: true

require 'yaml'
require_relative '../context_map'
require_relative 'brackets'

module Proscenium
  module CLI
    # Registers the contexts in pnpm-workspace.yaml (#154), as a textual splice so the file's other
    # settings, order and comments survive.
    module PnpmWorkspace
      # The `packages` key, plain or quoted, opening a flow list or a block, where root_pair finds
      # it, with the list's anchor if it has one.
      KEY = /(?:packages|'packages'|"packages")/
      ANCHOR = /(?:&[^\s\[\]{},]+[ \t]*)?/
      FLOW = /\G#{KEY}[ \t]*:[ \t]*#{ANCHOR}\[/
      BLOCK = /\G#{KEY}[ \t]*:[ \t]*#{ANCHOR}(#.*?)?\r?\n/

      module_function

      # Adds the pattern to `packages`, in the list's own style: a flow list, or a block list at
      # whatever indentation its items use. The result is parsed back; anything but the old list
      # plus the pattern, with every other key unchanged, is refused rather than written.
      def splice(text)
        return text if ContextMap.registered_in?('pnpm-workspace.yaml', text, strict: true)

        text = ContextMap.utf8(text)
        bom = text.start_with?(ContextMap::BOM) ? ContextMap::BOM : ''
        body = text.delete_prefix(bom)
        spliced = splice_body(body)
        verify(body, spliced)
        if ContextMap.excludes?(ContextMap.yaml_packages(spliced))
          raise Error.new('PSM-E-REGISTRATION-EXCLUDED', file: 'pnpm-workspace.yaml')
        end

        "#{bom}#{spliced}"
      end

      def splice_body(text)
        eol = text.include?("\r\n") ? "\r\n" : "\n"
        key, value = root_pair(text)
        at = key ? offset(text, key) : text.length # past the end, neither matches
        # Adding to an anchored list adds to every alias of it too.
        anchor = value.anchor if value.is_a?(Psych::Nodes::Sequence)
        raise refused if anchor && aliased?(text, anchor)

        if value.is_a?(Psych::Nodes::Alias)
          spell_out(text, value)
        elsif (flow = text.match(FLOW, at))
          close = Brackets.array_end(text, flow.end(0)) or raise refused
          insert_into_flow(text, flow.end(0), text[flow.end(0)...close], eol)
        elsif (key = text.match(BLOCK, at))
          indent = text[key.end(0)..][/\A(?:[ \t]*(?:#.*)?\r?\n)*([ \t]*)- /, 1] || '  '
          text.dup.insert(key.end(0), "#{indent}- #{ContextMap::REGISTRATION}#{eol}")
        else
          # A new key would override a list inherited through a merge key (`<<: *defaults`).
          raise refused if merges?(text)

          "packages:#{eol}  - #{ContextMap::REGISTRATION}#{eol}#{eol unless text.empty?}#{text}"
        end
      end

      def merges?(text)
        root = Psych.parse_stream(text).children.first&.root
        root.is_a?(Psych::Nodes::Mapping) &&
          root.children.each_slice(2).any? { |key, _| key.is_a?(Psych::Nodes::Scalar) && key.value == '<<' }
      rescue Psych::SyntaxError
        false
      end

      # The root mapping's `packages` key and its value, at any indentation, or nil. The last pair,
      # as pnpm and ContextMap read it; another mapping's `packages` key is not it.
      def root_pair(text)
        root = Psych.parse_stream(text).children.first&.root
        return unless root.is_a?(Psych::Nodes::Mapping)

        root.children.each_slice(2).reverse_each
            .find { |key, _| key.is_a?(Psych::Nodes::Scalar) && key.value == 'packages' }
      rescue Psych::SyntaxError
        nil
      end

      def aliased?(text, anchor)
        Psych.parse_stream(text).each.any? { it.is_a?(Psych::Nodes::Alias) && it.anchor == anchor }
      end

      def offset(text, node) = text.lines.first(node.start_line).sum(&:length) + node.start_column

      # `packages: *list` as a flow list of the entries it names plus the pattern, so the anchored
      # list stays as it is for anything else that uses it.
      def spell_out(text, node)
        entries = ContextMap.yaml_packages(text)
        raise refused unless entries&.all?(String)

        list = (entries + [ContextMap::REGISTRATION]).map { "'#{it.gsub("'", "''")}'" }.join(', ')
        start = offset(text, node)
        "#{text[0...start]}[#{list}]#{text[(start + node.end_column - node.start_column)..]}"
      end

      # Appends the pattern as the flow list's last item, on its own line when the items are, and
      # keeps a trailing comma.
      def insert_into_flow(text, start, body, eol)
        list = body.rstrip
        comma = list.end_with?(',')
        indent = body[/\n([ \t]*)\S/, 1]
        separator = if list.empty? then ''
                    elsif indent then "#{',' unless comma}#{eol}#{indent}"
                    else comma ? ' ' : ', '
                    end
        item = "'#{ContextMap::REGISTRATION}'#{',' if comma}"
        text.dup.insert(start + list.length, "#{separator}#{item}")
      end

      # The `packages` list of a document that is empty or a mapping, as ContextMap reads it.
      def packages(text)
        root = Psych.parse_stream(text).children.first&.root
        raise refused unless root.nil? || root.is_a?(Psych::Nodes::Mapping)

        ContextMap.yaml_packages(text)
      rescue Psych::SyntaxError
        raise refused
      end

      # The splice must add the pattern to `packages` and change nothing else.
      def verify(text, spliced)
        before = packages(text)
        after = packages(spliced)
        expected = Array(before) + [ContextMap::REGISTRATION]
        same = after.is_a?(Array) && after.tally == expected.tally
        raise refused unless same && others(spliced) == others(text)
      end

      # The document without its `packages` key, as YAML with aliases left unexpanded: comparing
      # expanded values could take forever on aliases that nest.
      def others(text)
        stream = Psych.parse_stream(text)
        mapping = stream.children.first&.root
        return '' unless mapping.is_a?(Psych::Nodes::Mapping)

        mapping.children.replace(mapping.children.each_slice(2).reject do |key, _|
          key.is_a?(Psych::Nodes::Scalar) && key.value == 'packages'
        end.flatten)
        mapping.children.empty? ? '' : stream.to_yaml
      end

      def refused = Error.new('PSM-E-REGISTRATION', file: 'pnpm-workspace.yaml')
    end
  end
end
