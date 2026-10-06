# frozen_string_literal: true

module Proscenium
  module CLI
    # Quote-aware bracket scanning for the textual splices of pnpm-workspace.yaml flow lists and
    # package.json (#154): a bracket or brace inside a quoted string is text, not structure.
    module Brackets
      module_function

      # The index of the `]` closing the flow list or JSON array whose `[` ends at `start`, or nil:
      # a bracket inside a quoted string, as a glob such as `packages/[ab]` has, or in a nested
      # list, does not close it.
      def array_end(text, start)
        depth = 0
        structure(text, start) do |char, index|
          if char == '['
            depth += 1
          elsif char == ']'
            return index if depth.zero?

            depth -= 1
          end
        end
        nil
      end

      # Where the first match of `key` from `from` at `depth` (1 for a JSON document's own keys)
      # ends, or nil: another object's key of the same name is not it.
      def key_end(text, key, depth, from = 0)
        text.to_enum(:scan, key).map { Regexp.last_match }
            .find { it.begin(0) >= from && depth(text, it.begin(0)) == depth }&.end(0)
      end

      # How deep `index` sits in `text`'s brackets and braces, outside quoted strings.
      def depth(text, index)
        nesting = { '[' => 1, '{' => 1, ']' => -1, '}' => -1 }
        structure(text).take_while { |_, at| at < index }.sum { |char, _| nesting.fetch(char, 0) }
      end

      # Each character of `text` from `from` that is outside a quoted string or a YAML comment, with
      # its index.
      def structure(text, from = 0)
        return enum_for(__method__, text, from) unless block_given?

        quote = nil
        index = from
        while index < text.length
          char = text[index]
          if quote
            index += 1 if char == '\\' && quote == '"'
            quote = nil if char == quote
          elsif ['"', "'"].include?(char)
            quote = char
          elsif char == '#' && (index.zero? || text[index - 1].match?(/[\s\[{,]/))
            # A YAML comment, to the end of its line, after a space or a flow delimiter, as Psych
            # reads it. JSON has no `#` outside a string.
            index = (text.index("\n", index) || text.length) - 1
          else
            yield char, index
          end
          index += 1
        end
      end
    end
  end
end
