# frozen_string_literal: true

module Proscenium
  # Resolves the given `class_names` as CSS module names for the given `module_path`.
  #
  # The transformed class names will be available as an Array at `#class_names`. The resolved
  # stylesheets will be available at `#stylesheets`, as a Hash containing the keys `:resolved_path`,
  # and `:digest`.
  #
  class CssModule::ClassNamesResolver
    # @param module_path [Pathname] of the CSS file.
    # @param class_names: [String,Array<String,Symbol>]
    def initialize(module_path, class_names: [])
      unless module_path.is_a?(Pathname)
        raise ArgumentError, "`module_path` '#{module_path}' must be a `Pathname`"
      end

      @class_names = class_names.is_a?(Array) ? class_names : class_names.split
      @module_path = module_path
      @stylesheets = {}

      resolve if @class_names.any?
    end

    def class_names
      @class_names.join(' ')
    end

    def stylesheets
      @stylesheets.map { |_, values| values[:resolved_path] }
    end

    # Resolves the class names to CSS modules, and returns the transformed class names, which will
    # also be available at `#class_names`.
    def resolve
      @class_names.map! do |class_name|
        resolve_class_name class_name
      end
    end

    # Resolve the given `class_name` to a CSS module name.
    # @param class_name [String,Symbol]
    # @return [String] the transformed CSS module name.
    def resolve_class_name(class_name) # rubocop:disable Metrics/AbcSize
      class_name = class_name.to_s if class_name.is_a?(Symbol)

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

        CssModule.transform_class_name name, digest: add_stylesheet("#{path}.module.css")[:digest]
      elsif class_name.starts_with?('@')
        CssModule.transform_class_name class_name[1..],
                                       digest: add_stylesheet(@module_path)[:digest]
      else
        class_name
      end
    end

    private

    def add_stylesheet(path)
      return @stylesheets[path] if @stylesheets.key?(path)

      resolved_path = Resolver.resolve(path.to_s)

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
