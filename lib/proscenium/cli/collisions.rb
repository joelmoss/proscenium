# frozen_string_literal: true

require 'json'
require 'yaml'
require_relative 'registration'

module Proscenium
  module CLI
    # The app's own packages that already take a gem context's name, `@rubygems/<gem>` (#154,
    # C05): a dependency on it that is not the context, such as the GitHub pin an app used before
    # adopting, and a workspace package so named. Install reads them before it writes anything.
    module Collisions
      module_function

      DEPENDENCY_FIELDS = %w[dependencies devDependencies optionalDependencies
                             peerDependencies].freeze

      # One line for each package of the app's own taking a context's name.
      def find(root, manager, gems)
        names = gems.to_h { ["@rubygems/#{it}", it] }
        app = read_json(File.join(root, 'package.json')) || {}
        pinned = DEPENDENCY_FIELDS.flat_map do |field|
          (app[field] || {}).filter_map do |name, spec|
            next if !names.key?(name) || context_workspace?(spec, name) ||
                    context_link?(root, spec, names[name])

            "package.json #{field} has #{name} as \"#{spec}\""
          end
        end
        pinned + workspace_packages(root, manager, app).filter_map do |file, name|
          "#{file} is named #{name}" if names.key?(name)
        end
      end

      # Whether `spec` is the workspace package `name`, the context: `workspace:<range>`, not an
      # alias to another package, `workspace:<other>@<range>`.
      def context_workspace?(spec, name)
        range = spec.to_s.delete_prefix('workspace:')
        return false if range == spec.to_s

        aliased = range[/\A(@?[^@]+)@/, 1]
        aliased.nil? || aliased == name
      end

      # Whether `spec` links to the gem's own context, however the path is spelled.
      def context_link?(root, spec, gem)
        return false unless spec.to_s.start_with?('link:')

        context = File.join(File.expand_path(root), ContextMap::CONTEXTS, gem)
        File.expand_path(spec.to_s.delete_prefix('link:'), root) == context
      end

      # [package.json path, package name] for each workspace package the app declares, other than
      # the contexts. A pattern starting with `!` excludes. `./` is dropped from each, as pnpm and
      # Bun read `./packages/*` and `packages/*` alike.
      def workspace_packages(root, manager, app)
        excluded, included = workspace_patterns(root, manager, app)
                             .grep(String).reject { ContextMap.registration?(it) }
                             .map { it.sub(%r{\A(!?)\./}, '\\1') }
                             .partition { it.start_with?('!') }
        files = included.flat_map { Dir.glob(File.join(it, 'package.json'), base: root) }.uniq
        files.filter_map do |file|
          dir = File.dirname(file)
          next if dir.split('/').include?('node_modules')

          # FNM_EXTGLOB for braces, which pnpm and Bun expand, as Dir.glob does for the inclusions.
          flags = File::FNM_PATHNAME | File::FNM_EXTGLOB
          next if excluded.any? { File.fnmatch?(it[1..], dir, flags) }

          [file, read_json(File.join(root, file))&.dig('name')]
        end
      end

      def workspace_patterns(root, manager, app)
        if manager == 'bun'
          workspaces = app['workspaces']
          Array(workspaces.is_a?(Hash) ? workspaces['packages'] : workspaces)
        else
          path = File.join(root, 'pnpm-workspace.yaml')
          File.exist?(path) ? Array(ContextMap.yaml_packages(File.read(path))) : []
        end
      rescue Psych::SyntaxError
        [] # the manager reports it
      end

      def read_json(path)
        json = File.exist?(path) && ContextMap.read_json(path)
        json.is_a?(Hash) ? json : nil
      rescue JSON::ParserError
        nil
      end
    end
  end
end
