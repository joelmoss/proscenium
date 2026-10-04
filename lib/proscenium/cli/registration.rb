# frozen_string_literal: true

require 'json'

module Proscenium
  module CLI
    # The one-time edits that register `.proscenium/packages/*` with the app's package manager, and
    # the `.gitignore` lines for Proscenium's own state (#154). Each is a textual splice, so the
    # file's other settings, order and comments survive; each is computed without writing, so
    # `install` can print it as a diff first.
    module Registration
      PATTERN = '.proscenium/packages/*'
      IGNORES = ['.proscenium/*', '!.proscenium/packages/',
                 '.proscenium/packages/*/node_modules/'].freeze

      module_function

      # The edits the project at `root` needs: [path, current text, new text] for each file that
      # changes. Empty once registered.
      def edits(root, manager)
        file = manager == 'bun' ? 'package.json' : 'pnpm-workspace.yaml'
        [[file, method(manager == 'bun' ? :splice_package_json : :splice_pnpm_workspace)],
         ['.gitignore', method(:splice_gitignore)]].filter_map do |name, splice|
          path = File.join(root, name)
          text = File.exist?(path) ? File.read(path) : ''
          spliced = splice.call(text)
          [path, text, spliced] unless spliced == text
        end
      end

      # Whether the app has adopted the bridge: its committed registration names the contexts.
      def registered?(root, manager)
        file = File.join(root, manager == 'bun' ? 'package.json' : 'pnpm-workspace.yaml')
        File.exist?(file) && File.read(file).include?(PATTERN)
      end

      def splice_pnpm_workspace(text)
        return text if text.include?(PATTERN)

        if (flow = text.match(/^packages:[ \t]*\[(?<list>[^\]]*)\](?<rest>.*)$/))
          list = [flow[:list].strip, "'#{PATTERN}'"].reject(&:empty?).join(', ')
          text.sub(flow[0], "packages: [#{list}]#{flow[:rest]}")
        elsif text.match?(/^packages:[ \t]*(#.*)?$/)
          text.sub(/^packages:[ \t]*(#.*)?\n?/) { "#{it.chomp}\n  - #{PATTERN}\n" }
        else
          "packages:\n  - #{PATTERN}\n#{"\n" unless text.empty?}#{text}"
        end
      end

      # Adds the pattern to package.json's `workspaces`, as an array or an object's `packages`,
      # or adds the key. Refuses rather than guess at JSON it cannot splice.
      def splice_package_json(text)
        return text if text.include?(PATTERN)

        json = text.empty? ? {} : JSON.parse(text)
        spliced = if (array = text.match(/"workspaces"\s*:\s*\[/) ||
                              text.match(/"workspaces"\s*:\s*\{[^}]*"packages"\s*:\s*\[/))
                    insert_into_array(text, array.end(0))
                  else
                    add_key(text, json)
                  end
        expected = expected_workspaces(json)
        actual = JSON.parse(spliced)['workspaces']
        actual = actual['packages'] if actual.is_a?(Hash)
        raise Error.new('PSM-E-REGISTRATION', file: 'package.json') unless actual == expected

        spliced
      end

      def expected_workspaces(json)
        current = json['workspaces']
        current = current['packages'] if current.is_a?(Hash)
        (current || []) + [PATTERN]
      end

      # Appends the pattern as the last element of the array whose `[` ends at `start`.
      def insert_into_array(text, start)
        close = text.index(']', start)
        body = text[start...close]
        if body.strip.empty?
          "#{text[0...start]}\"#{PATTERN}\"#{text[close..]}"
        else
          last = start + body.rstrip.length
          indent = body[/\n([ \t]*)\S/, 1]
          separator = indent ? ",\n#{indent}" : ', '
          "#{text[0...last]}#{separator}\"#{PATTERN}\"#{text[last..]}"
        end
      end

      # Adds `"workspaces": [pattern]` as the first key, in the file's own indentation.
      def add_key(text, json)
        return "#{JSON.pretty_generate('workspaces' => [PATTERN])}\n" if text.strip.empty?

        open = text.index('{') + 1
        indent = text[/\{\s*\n([ \t]+)/, 1]
        if indent
          "#{text[0...open]}\n#{indent}\"workspaces\": [\"#{PATTERN}\"]#{',' unless json.empty?}" \
            "#{text[open..]}"
        else
          "#{text[0...open]}\"workspaces\": [\"#{PATTERN}\"]#{', ' unless json.empty?}" \
            "#{text[open..]}"
        end
      end

      # Appends the lines Proscenium owns, and a node_modules rule if the app has none (Bun moves
      # an old tree to node_modules/.old_modules-<hash> when its linker changes).
      def splice_gitignore(text)
        lines = text.lines(chomp: true)
        wanted = IGNORES.reject { lines.include?(it) }
        wanted.unshift('node_modules/') unless lines.any? { it.match?(%r{\A/?node_modules/?\z}) }
        return text if wanted.empty?

        separator = text.empty? || text.end_with?("\n") ? '' : "\n"
        "#{text}#{separator}#{"\n" unless text.empty?}# Proscenium\n#{wanted.join("\n")}\n"
      end
    end
  end
end
