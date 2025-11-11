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
    # @param names [String,Symbol,Array<String,Symbol>]
    # @param require_prefix: [Boolean] whether or not to require the `@` prefix.
    # @return [Array<String>] the transformed CSS module names.
    def class_names(*names, require_prefix: true)
      names.map do |name|
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

          class_name! name, original_name, path: "#{path}#{FILE_EXT}"
        elsif name.start_with?('@')
          class_name! name[1..], original_name
        else
          require_prefix ? name : class_name!(name, original_name)
        end
      end
    end

    def class_name!(name, original_name, path: @source_path)
      unless path
        raise Proscenium::CssModule::TransformError.new(original_name, 'CSS module path not given')
      end

      manifest_path, non_manifest_path, abs_path = Resolver.resolve(path.to_s, as_array: true)
      digest = Importer.import(manifest_path || non_manifest_path, digest: lambda {
        Utils.css_module_digest abs_path
      })

      transformed_path = ''
      if Rails.env.development?
        rel_path = Pathname.new(abs_path).relative_path_from(Rails.root).sub_ext('')
        transformed_path = "_#{rel_path.to_s.gsub(%r{[@/.+]}, '-')}"
      end

      transformed_name = name.to_s
      transformed_name = if transformed_name.start_with?('_')
                           "_#{transformed_name[1..]}_#{digest}#{transformed_path}"
                         else
                           "#{transformed_name}_#{digest}#{transformed_path}"
                         end

      [transformed_name, non_manifest_path]
    end
  end
end
