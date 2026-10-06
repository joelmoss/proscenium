# frozen_string_literal: true

require 'json'
require_relative '../context_map'
require_relative 'manager'

module Proscenium
  module CLI
    # The Bun linker an app uses today, written into bunfig.toml when the app sets none (#154,
    # C48). Registering contexts adds `workspaces`, and with no linker set that alone can switch
    # Bun from a hoisted node_modules to its isolated store (Stage A), so the first install pins
    # the layout the app already has. Shown in the registration diff before it is written.
    module BunLinker
      # An `[install]` header, its name bare or quoted, and any comment after it.
      HEADER = /^\[[ \t]*#{Manager::INSTALL}[ \t]*\][ \t]*(?:#[^\r\n]*)?(?=\r?$)/

      module_function

      # Bun's names for each layout: `node-linker`'s, and `install-strategy`'s, which node-linker
      # overrides (probed on Bun 1.4.2).
      NODE_LINKERS = { 'isolated' => 'isolated', 'pnpm' => 'isolated', 'hoisted' => 'hoisted',
                       'npm' => 'hoisted' }.freeze
      STRATEGIES = { 'linked' => 'isolated', 'hoisted' => 'hoisted', 'nested' => 'hoisted' }.freeze
      NPMRC_LINKER = /^[ \t]*(node-linker|install-strategy)[ \t]*=[ \t]*["']?([^\s"']+)/

      # The linker the project's .npmrc chooses. Otherwise `isolated` if Bun's isolated store is
      # there, `hoisted` for any other node_modules. With nothing installed yet: what Bun would
      # pick for the app as it stands, which is isolated only for an app that already declares
      # workspaces under a lock of configVersion 1 or later.
      def current(root)
        chosen = configured(root)
        return chosen if chosen

        modules = File.join(root, 'node_modules')
        return 'isolated' if File.directory?(File.join(modules, '.bun'))
        return 'hoisted' if File.directory?(modules)

        workspaces?(root) && config_version(root) >= 1 ? 'isolated' : 'hoisted'
      end

      # bunfig.toml's text with `linker` set in its `[install]` table, adding the table if need be.
      def splice(text, linker)
        line = "linker = \"#{linker}\""
        eol = text.include?("\r\n") ? "\r\n" : "\n"
        if (header = text.match(HEADER))
          text.dup.insert(header.end(0), "#{eol}#{line}")
        else
          separator = text.empty? || text.end_with?("\n") ? '' : eol
          "#{text}#{separator}#{eol unless text.empty?}[install]#{eol}#{line}#{eol}"
        end
      end

      # The linker the project's own .npmrc sets. Bun also reads the developer's ~/.npmrc,
      # $XDG_CONFIG_HOME/.npmrc and global .bunfig.toml, but this is committed for the whole team,
      # so only the project decides it.
      def configured(root) = npmrc_linker(File.join(root, '.npmrc'))

      # The linker an .npmrc sets, by node-linker or else install-strategy, or nil.
      def npmrc_linker(path)
        return unless File.exist?(path)

        settings = File.read(path).scan(NPMRC_LINKER).to_h
        NODE_LINKERS[settings['node-linker']] || STRATEGIES[settings['install-strategy']]
      end

      def workspaces?(root)
        path = File.join(root, 'package.json')
        File.exist?(path) && ContextMap.read_json(path).key?('workspaces')
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
