# frozen_string_literal: true

module Proscenium
  class CssModule::Transformer
    FILE_EXT = '.module.css'

    def self.class_names(path, *names)
      new(path).class_names(*names)
    end

    def initialize(source_path)
      return unless (@source_path = source_path)

      @source_path = Pathname.new(@source_path) unless @source_path.is_a?(Pathname)
      @source_path = @source_path.sub_ext(FILE_EXT) unless @source_path.to_s.end_with?(FILE_EXT)
    end

    # Transform each of the given class `names` to their respective CSS module name, which consist
    # of the name, and suffixed with the digest of the resolved source path.
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
    # When a block is given, it is yielded once per input name with
    # `(transformed_name, side_load_path)`. `side_load_path` is the exact string passed to
    # `Importer.import` for that name, or `nil` for names that did not trigger a side-load (plain
    # class names with `require_prefix: true`). The return value is unchanged — callers that don't
    # need the path can keep ignoring the block.
    #
    # @param names [String,Symbol,Array<String,Symbol>]
    # @param require_prefix: [Boolean] whether or not to require the `@` prefix.
    # @yieldparam transformed_name [String]
    # @yieldparam side_load_path [String, nil]
    # @return [Array<String>] the transformed CSS module names.
    def class_names(*names, require_prefix: true)
      names.map do |name|
        transformed, path = transform_class_name(name, require_prefix: require_prefix)
        yield(transformed, path) if block_given?
        transformed
      end
    end

    def class_name!(name, original_name, path: @source_path)
      unless path
        raise Proscenium::CssModule::TransformError.new(original_name, 'CSS module path not given')
      end

      digest = Importer.import(path.to_s)

      transformed_name = name.to_s
      if transformed_name.start_with?('_')
        "_#{transformed_name[1..]}_#{digest}"
      else
        "#{transformed_name}_#{digest}"
      end
    end

    private

    # Returns `[transformed_name, side_load_path]` for a single class-name reference.
    # `side_load_path` is the exact string that `class_name!` passed to `Importer.import`, or
    # `nil` if the name did not trigger a side-load. Extracted so `#class_names` can yield paths
    # to consumers (e.g. proscenium-phlex's `resolved_css_module_paths` replay registry) without
    # re-parsing names.
    def transform_class_name(name, require_prefix:)
      original_name = name.dup
      name = name.to_s if name.is_a?(Symbol)

      if name.include?('/')
        if name.start_with?('@')
          # Scoped bare specifier (eg. "@scoped/package/lib/button@default").
          _, path, name = name.split('@')
          path = "@#{path}"
        else
          # Local path (eg. /some/path/to/button@default") or bare specifier (eg.
          # "mypackage/lib/button@default").
          path, name = name.split('@')
        end

        module_path = "#{path}#{FILE_EXT}"
        [class_name!(name, original_name, path: module_path), module_path]
      elsif name.start_with?('@')
        [class_name!(name[1..], original_name), @source_path&.to_s]
      elsif require_prefix
        [name, nil]
      else
        [class_name!(name, original_name), @source_path&.to_s]
      end
    end
  end
end
