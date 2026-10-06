# frozen_string_literal: true

require 'json'
require_relative '../context_map'
require_relative 'bun_linker'
require_relative 'brackets'
require_relative 'gitignore'
require_relative 'pnpm_workspace'
require_relative 'manager'

module Proscenium
  module CLI
    # The one-time edits that register `.proscenium/packages/*` with the app's package manager, and
    # the `.gitignore` lines for Proscenium's own state (#154, Gitignore). Each is a textual
    # splice, so the file's other settings, order and comments survive; each is computed without
    # writing, so `install` can print it as a diff first.
    module Registration
      PATTERN = ContextMap::REGISTRATION

      module_function

      # The edits the project at `root` needs: [path, current text, new text] for each file that
      # changes. Empty once registered.
      def edits(root, manager)
        file = manager == 'bun' ? 'package.json' : 'pnpm-workspace.yaml'
        registration = if manager == 'bun' then method(:splice_package_json)
                       else PnpmWorkspace.method(:splice)
                       end
        splices = [[file, registration],
                   ['.gitignore', Gitignore.method(:splice)]]
        if manager == 'bun' && !Manager.new('bun', root).bun_linker
          linker = BunLinker.current(root)
          splices << ['bunfig.toml', ->(text) { BunLinker.splice(text, linker) }]
        end
        splices.filter_map do |name, splice|
          path = File.join(root, name)
          text = File.exist?(path) ? File.read(path) : ''
          spliced = splice.call(text)
          next if spliced == text
          # Writing through a link could change a file outside the app.
          raise Error.new('PSM-E-OWNED-LINK', paths: name) if File.symlink?(path)

          [path, text, spliced]
        end
      end

      # Whether the app has adopted the bridge: its committed registration names the contexts.
      def registered?(root, manager)
        ContextMap.registers?(root, manager == 'bun' ? 'package.json' : 'pnpm-workspace.yaml')
      end

      def refused(file) = Error.new('PSM-E-REGISTRATION', file:)

      # Adds the pattern to package.json's `workspaces`, as an array or an object's `packages`,
      # or adds the key. Refuses rather than guess at JSON it cannot splice. A byte order mark is
      # kept.
      def splice_package_json(text)
        return text if ContextMap.registered_in?('package.json', text, strict: true)

        bom = text.start_with?("\uFEFF") ? "\uFEFF" : ''
        spliced = splice_json(text.delete_prefix(bom))
        if ContextMap.excludes?(ContextMap.json_workspaces(spliced))
          raise Error.new('PSM-E-REGISTRATION-EXCLUDED', file: 'package.json')
        end

        "#{bom}#{spliced}"
      end

      def splice_json(text)
        json = text.empty? ? {} : JSON.parse(text)
        raise refused('package.json') unless json.is_a?(Hash)

        current = json['workspaces']
        spliced = if current.nil?
                    add_key(text, json)
                  elsif current.is_a?(Array)
                    insert_into_array(text, key_end(text, /"workspaces"\s*:\s*\[/, 1))
                  elsif current.is_a?(Hash) && current['packages'].is_a?(Array)
                    object = key_end(text, /"workspaces"\s*:\s*\{/, 1)
                    insert_into_array(text, key_end(text, /"packages"\s*:\s*\[/, 2, object))
                  else
                    raise refused('package.json')
                  end
        verify_json(json, spliced)
        spliced
      rescue JSON::ParserError
        raise refused('package.json')
      end

      def key_end(...) = Brackets.key_end(...) || raise(refused('package.json'))

      def verify_json(before, spliced)
        after = JSON.parse(spliced)
        expected = expected_workspaces(before)
        actual = after['workspaces']
        actual = actual['packages'] if actual.is_a?(Hash)
        same = after.except('workspaces') == before.except('workspaces')
        raise refused('package.json') unless actual == expected && same
      end

      def expected_workspaces(json)
        current = json['workspaces']
        current = current['packages'] if current.is_a?(Hash)
        (current || []) + [PATTERN]
      end

      # Appends the pattern as the last element of the array whose `[` ends at `start`.
      def insert_into_array(text, start)
        close = Brackets.array_end(text, start) or raise refused('package.json')
        body = text[start...close]
        if body.strip.empty?
          "#{text[0...start]}\"#{PATTERN}\"#{text[close..]}"
        else
          last = start + body.rstrip.length
          indent = body[/\n([ \t]*)\S/, 1]
          separator = indent ? ",#{eol(text)}#{indent}" : ', '
          "#{text[0...last]}#{separator}\"#{PATTERN}\"#{text[last..]}"
        end
      end

      # Adds `"workspaces": [pattern]` as the first key, in the file's own indentation.
      def add_key(text, json)
        return "#{JSON.pretty_generate('workspaces' => [PATTERN])}\n" if text.strip.empty?

        open = text.index('{') + 1
        indent = text[/\{\s*\n([ \t]+)/, 1]
        if indent
          "#{text[0...open]}#{eol(text)}#{indent}\"workspaces\": [\"#{PATTERN}\"]" \
            "#{',' unless json.empty?}#{text[open..]}"
        else
          "#{text[0...open]}\"workspaces\": [\"#{PATTERN}\"]#{', ' unless json.empty?}" \
            "#{text[open..]}"
        end
      end

      def eol(text) = text.include?("\r\n") ? "\r\n" : "\n"
    end
  end
end
