# frozen_string_literal: true

require 'rails/generators/base'

module Proscenium
  module Generators
    # Sets up `bun test` so it can import the same JS, TS, JSX and CSS the app serves.
    #
    #   rails generate proscenium:bun
    #
    # Safe to run more than once: the preload is created if missing, and bunfig.toml is merged
    # rather than overwritten, because an app may already have one with its own preloads.
    class BunGenerator < Rails::Generators::Base
      PRELOAD_PATH = 'test/proscenium.preload.js'
      PRELOAD_ENTRY = './test/proscenium.preload.js'
      BUNFIG_PATH = 'bunfig.toml'

      source_root File.expand_path('templates', __dir__)

      desc 'Configure bun test to run against your Proscenium-bundled JavaScript.'

      def create_preload
        template 'proscenium.preload.js', PRELOAD_PATH
      end

      def configure_bunfig
        return create_file(BUNFIG_PATH, default_bunfig) unless File.exist?(bunfig_full_path)

        contents = File.read(bunfig_full_path)

        if already_preloaded?(contents)
          say_status :identical, BUNFIG_PATH, :blue
        elsif (updated = with_preload(contents))
          File.write(bunfig_full_path, updated)
          say_status :update, BUNFIG_PATH, :green
        else
          say_manual_step
        end
      end

      def report
        say ''
        say 'Now write a test that imports your app code, and run `bun test`:'
        say ''
        say '  // test/js/button.test.jsx'
        say '  import { expect, test } from "bun:test";'
        say '  import Button from "/app/components/button.jsx";'
        say ''
      end

      private

      # Only a real entry counts. The bare string can also appear in a commented-out line, and
      # reporting "identical" then would silently do nothing for someone who had disabled it.
      def already_preloaded?(contents)
        test_table(contents).to_s.match?(/^[^#\n]*["']#{Regexp.escape(PRELOAD_ENTRY)}["']/o)
      end

      # Returns the whole file with our entry added inside the `[test]` table, or nil when that
      # cannot be done without risking the file.
      #
      # Editing TOML with a regex is how this went wrong before, so the rules are narrow and each
      # refusal falls through to printing the two lines for the user to add:
      #
      #   - a `preload` key outside `[test]` is left alone. It belongs to `bun run`, and appending
      #     to it put the test preload somewhere `bun test` never reads.
      #   - `[test]` already present without a `preload` key gets the key inserted into it. The
      #     previous version appended a second `[test]` table, which is invalid TOML.
      #   - an existing `[test] preload` array is extended in place, respecting a trailing comma.
      #     Appending `, "entry"` after one produced `,\n, "entry"`, also invalid TOML.
      def with_preload(contents)
        table = test_table(contents)

        return "#{contents.sub(/\n*\z/, "\n")}\n#{default_bunfig}" if table.nil?

        if (array = table[/^[^#\n]*\bpreload\s*=\s*\[.*?\]/m])
          extended = extend_array(array)
          return nil if extended.nil?

          # Substituted inside the table, then the table inside the document. `contents.sub(array)`
          # replaces the FIRST occurrence of that text anywhere - so a root-level `preload` holding
          # the same entries as `[test]`'s got edited instead, which put the harness in `bun run`,
          # left `bun test` without it, and reported success.
          return contents.sub(table) { table.sub(array) { extended } }
        end

        # `[test]` exists but has no preload key: put one directly under its header.
        header = table[/\A\[test\][^\n]*\n/]
        return nil if header.nil?

        contents.sub(table) { table.sub(header, %(#{header}preload = ["#{PRELOAD_ENTRY}"]\n)) }
      end

      # The `[test]` table's text, from its header to the next table header or end of file. Nil
      # when the file has no `[test]` table.
      # The header line may end at EOF rather than a newline. Requiring the newline made a bunfig
      # whose last line is `[test]` look like it had no `[test]` table at all, and the nil branch
      # above then appended a second one - the invalid-TOML shape this rewrite exists to avoid.
      # Matching it here instead leaves `with_preload` unable to find a header to insert under, so
      # it refuses and prints the two lines for the user to add.
      def test_table(contents)
        contents[/^\[test\][^\n]*(?:\n|\z).*?(?=^\[|\z)/m]
      end

      # Adds our entry to an existing array, keeping the file's own shape. A trailing comma is
      # respected rather than doubled - appending ", entry" after one is what produced invalid
      # TOML before. Returns nil when the array's shape is one this cannot edit safely.
      def extend_array(array)
        inner = array[/\[(.*)\]/m, 1]
        entry = %("#{PRELOAD_ENTRY}")

        return array.sub(/\[\s*\]/m, "[#{entry}]") if inner.strip.empty?

        # A comment after the last entry swallows the separator: the inserted `, ` lands inside
        # `# DOM shim` and the two entries end up with no comma between them - valid input, invalid
        # output. Putting the comma before the comment means parsing TOML comments, which is the
        # approximation this file keeps getting punished for. Refuse and let the user do it.
        # A comment after the last entry swallows the separator: the inserted `, ` lands inside
        # `# DOM shim` and the two entries end up with no comma between them - valid input, invalid
        # output. Putting the comma before the comment means parsing TOML comments, which is the
        # approximation this file keeps getting punished for. Refuse and let the user do it.
        return nil if inner.match?(/(?<!["'])#/)

        separator = inner.rstrip.end_with?(',') ? '' : ', '
        array.sub(/(\s*)\]\z/) { "#{separator}#{::Regexp.last_match(1)}#{entry}]" }
      end

      def say_manual_step
        say_status :skip, BUNFIG_PATH, :yellow
        say ''
        say "  Could not edit #{BUNFIG_PATH} safely. Add this to it by hand:"
        say ''
        say '    [test]'
        say %(    preload = ["#{PRELOAD_ENTRY}"])
        say ''
      end

      def bunfig_full_path
        File.expand_path(BUNFIG_PATH, destination_root)
      end

      def default_bunfig
        <<~TOML
          [test]
          preload = ["#{PRELOAD_ENTRY}"]
        TOML
      end
    end
  end
end
