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

        if contents.include?(PRELOAD_ENTRY)
          say_status :identical, BUNFIG_PATH, :blue
        elsif contents.match?(/^\s*preload\s*=/)
          inject_into_existing_preload(contents)
        else
          append_to_file BUNFIG_PATH, "\n#{default_bunfig}"
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

      def bunfig_full_path
        File.expand_path(BUNFIG_PATH, destination_root)
      end

      def default_bunfig
        <<~TOML
          [test]
          preload = ["#{PRELOAD_ENTRY}"]
        TOML
      end

      # Adds our entry to whatever preload list is already there, leaving the rest of the file
      # alone. Only the first `preload =` is touched - a bunfig with several is unusual enough that
      # guessing which one to edit would be worse than saying so.
      def inject_into_existing_preload(contents)
        updated = contents.sub(/^(\s*preload\s*=\s*\[)(.*?)(\])/m) do
          open_bracket, entries, close_bracket = Regexp.last_match.captures
          separator = entries.strip.empty? ? '' : ', '

          "#{open_bracket}#{entries}#{separator}\"#{PRELOAD_ENTRY}\"#{close_bracket}"
        end

        if updated == contents
          say_status :skip, "#{BUNFIG_PATH} - add #{PRELOAD_ENTRY} to its preload list by hand",
                     :yellow
        else
          File.write(bunfig_full_path, updated)
          say_status :update, BUNFIG_PATH, :green
        end
      end
    end
  end
end
