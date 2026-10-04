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
            next if !names.key?(name) || spec.to_s.start_with?('workspace:')

            "package.json #{field} has #{name} as \"#{spec}\""
          end
        end
        pinned + workspace_packages(root, manager, app).filter_map do |file, name|
          "#{file} is named #{name}" if names.key?(name)
        end
      end

      # [package.json path, package name] for each workspace package the app declares, other than
      # the contexts. A pattern starting with `!` excludes.
      def workspace_packages(root, manager, app)
        excluded, included = (workspace_patterns(root, manager, app) - [Registration::PATTERN])
                             .partition { it.start_with?('!') }
        files = included.flat_map { Dir.glob(File.join(it, 'package.json'), base: root) }.uniq
        files.filter_map do |file|
          dir = File.dirname(file)
          next if dir.split('/').include?('node_modules')
          next if excluded.any? { File.fnmatch?(it[1..], dir, File::FNM_PATHNAME) }

          [file, read_json(File.join(root, file))&.dig('name')]
        end
      end

      def workspace_patterns(root, manager, app)
        if manager == 'bun'
          workspaces = app['workspaces']
          Array(workspaces.is_a?(Hash) ? workspaces['packages'] : workspaces)
        else
          path = File.join(root, 'pnpm-workspace.yaml')
          File.exist?(path) ? Array(YAML.safe_load_file(path)&.dig('packages')) : []
        end
      rescue Psych::SyntaxError
        [] # the manager reports it
      end

      def read_json(path)
        json = File.exist?(path) && JSON.parse(File.read(path))
        json.is_a?(Hash) ? json : nil
      rescue JSON::ParserError
        nil
      end
    end
  end
end
