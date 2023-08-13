# frozen_string_literal: true

module Proscenium
  class CssModule::Transformer
    def self.class_names(path, *names)
      new(path).class_names(*names)
    end

    def initialize(source_path)
      source_path = Pathname.new(source_path) unless source_path.is_a?(Pathname)
      @source_path = source_path.sub_ext('.module.css')
    end

    # Transform each of the given class `names` to their respective CSS module name, which consist
    # of the camelCased name (lower case first character), and suffixed with the digest of the
    # resolved source path.
    #
    # Any name beginning with '@' will be transformed to a CSS module name. If `require_prefix` is
    # false, then all names will be transformed to a CSS module name regardless of whether or not
    # they begin with '@'.
    #
    #   class_names :@my_module_name, :my_class_name
    #
    # Note that the generated digest is based on the resolved (URL) path, not the original path.
    #
    # You can also provide a path specifier and class name. The path will be the URL path to a
    # stylesheet. The class name will be the name of the class to transform.
    #
    #   class_names "/lib/button@default"
    #   class_names "mypackage/button@large"
    #   class_names "@scoped/package/button@small"
    #
    # @param names [String,Symbol,Array<String,Symbol>]
    # @param require_prefix: [Boolean] whether or not to require the `@` prefix.
    # @raise [CssModule::StylesheetNotFound] if the path to the stylesheet does not exist.
    # @return [Array<String>] the transformed CSS module names.
    def class_names(*names, require_prefix: true)
      names.map do |name|
        name = name.to_s if name.is_a?(Symbol)

        if name.include?('/')
          if name.start_with?('@')
            # Scoped bare specifier (eg. "@scoped/package/lib/button@default").
            _, path, name = name.split('@')
            path = "@#{path}"
          elsif name.start_with?('/')
            # Local path with leading slash.
            path, name = name[1..].split('@')
          else
            # Bare specifier (eg. "mypackage/lib/button@default").
            path, name = name.split('@')
          end

          class_name! name, path: "#{path}.module.css"
        elsif name.start_with?('@')
          class_name! name[1..]
        else
          require_prefix ? name : class_name!(name)
        end
      end
    end

    # @raise [CssModule::StylesheetNotFound] if the stylesheet does not exist.
    def class_name!(name, path: @source_path)
      resolved_path = Resolver.resolve(path.to_s)

      unless Rails.root.join(resolved_path[1..]).exist?
        raise CssModule::StylesheetNotFound, resolved_path
      end

      digest = Importer.import(resolved_path)

      sname = name.to_s
      if sname.start_with?('_')
        "_#{sname[1..].camelize(:lower)}#{digest}"
      else
        "#{sname.camelize(:lower)}#{digest}"
      end
    end
  end
end
