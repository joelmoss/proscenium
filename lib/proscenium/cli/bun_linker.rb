# frozen_string_literal: true

require 'json'

module Proscenium
  module CLI
    # The Bun linker an app uses today, written into bunfig.toml when the app sets none (#154,
    # C48). Registering contexts adds `workspaces`, and with no linker set that alone can switch
    # Bun from a hoisted node_modules to its isolated store (Stage A), so the first install pins
    # the layout the app already has. Shown in the registration diff before it is written.
    module BunLinker
      module_function

      # `isolated` if Bun's isolated store is there, `hoisted` for any other node_modules. With
      # nothing installed yet: what Bun would pick for the app as it stands, which is isolated only
      # for an app that already declares workspaces under a lock of configVersion 1 or later.
      def current(root)
        modules = File.join(root, 'node_modules')
        return 'isolated' if File.directory?(File.join(modules, '.bun'))
        return 'hoisted' if File.directory?(modules)

        workspaces?(root) && config_version(root) >= 1 ? 'isolated' : 'hoisted'
      end

      # bunfig.toml's text with `linker` set in its `[install]` table, adding the table if need be.
      def splice(text, linker)
        line = "linker = \"#{linker}\""
        if (header = text.match(/^\[install\][ \t]*(#.*)?$/))
          text.sub(header[0]) { "#{it}\n#{line}" }
        else
          separator = text.empty? || text.end_with?("\n") ? '' : "\n"
          "#{text}#{separator}#{"\n" unless text.empty?}[install]\n#{line}\n"
        end
      end

      def workspaces?(root)
        path = File.join(root, 'package.json')
        File.exist?(path) && JSON.parse(File.read(path)).key?('workspaces')
      rescue JSON::ParserError
        false
      end

      def config_version(root)
        path = File.join(root, 'bun.lock')
        File.exist?(path) ? File.read(path)[/"configVersion":\s*(\d+)/, 1].to_i : 0
      end
    end
  end
end
