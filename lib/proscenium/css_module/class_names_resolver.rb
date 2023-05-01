# frozen_string_literal: true

module Proscenium
  class CssModule::ClassNamesResolver
    def initialize(class_names, phlex_path)
      @class_names = class_names.split
      @stylesheets = {}
      @phlex_path = phlex_path.sub_ext('.module.css')

      resolve_class_names
    end

    def class_names
      @class_names.join(' ')
    end

    def stylesheets
      @stylesheets.map { |_, values| values[:resolved_path] }
    end

    private

    def resolve_class_names
      @class_names.map! do |class_name|
        if class_name.include?('/')
          if class_name.starts_with?('@')
            # Scoped bare specifier (eg. "@scoped/package/lib/button@default").
            _, path, name = class_name.split('@')
            path = "@#{path}"
          elsif class_name.starts_with?('/')
            # Local path with leading slash.
            path, name = class_name[1..].split('@')
          else
            # Bare specifier (eg. "mypackage/lib/button@default").
            path, name = class_name.split('@')
          end

          path += '.module.css'
        else
          path = @phlex_path
          name = class_name[1..]
        end

        Utils.css_modularise_class_name name, digest: add_stylesheet(path)[:digest]
      end
    end

    def add_stylesheet(path)
      return @stylesheets[path] if @stylesheets.key?(path)

      resolved_path = Utils.resolve_path(path.to_s)

      unless Rails.root.join(resolved_path[1..]).exist?
        raise CssModule::StylesheetNotFound, resolved_path
      end

      # Note that the digest is based on the resolved (URL) path, not the original path.
      @stylesheets[path] = {
        resolved_path: resolved_path,
        digest: Utils.digest(resolved_path)
      }
    end
  end
end
