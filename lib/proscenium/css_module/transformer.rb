# frozen_string_literal: true

module Proscenium
  class CssModule::Transformer
    def initialize(source_path)
      @source_path = source_path.sub_ext('.module.css')
    end

    # Parses the given `content` for CSS modules names ('class' attributes beginning with '@'), and
    # returns the content with said CSS Modules replaced with the compiled class names.
    #
    # Example:
    #   <div class="@my_css_module_name"></div>
    #   // => <div class="myCssModuleNameABCD1234"></div>
    #
    # @param content [String] of HTML to parse for CSS modules.
    # @raise [CssModule::StylesheetNotFound] if the stylesheet does not exist.
    # @returns [String] the given `content` with CSS modules replaced with transformed class names.
    def transform_content!(content)
      doc = Nokogiri::HTML::DocumentFragment.parse(content)

      return content if (modules = doc.css('[class*="@"]')).empty?

      modules.each do |ele|
        ele['class'] = class_names(*ele.classes).join(' ')
      end

      doc.to_html.html_safe
    end

    # Transform each of the given class `names` to their respective CSS module name, which consist
    # of the camelCased name (lower case first character), and suffixed with the digest of the
    # resolved source path.
    #
    # Any name beginning with '@' will be transformed to a CSS module name. If `require_prefix` is
    # false, then all names will be transformed to a CSS module name regardless of whether or not
    # they begin with '@'.
    #
    # Note that the generated digest is based on the resolved (URL) path, not the original path.
    #
    # @param names [String,Symbol,Array<String,Symbol>]
    # @param require_prefix: [Boolean] whether or not to require the `@` prefix.
    # @return [Array<String>] the transformed CSS module names.
    def class_names(*names, require_prefix: true)
      names.map do |name|
        name = name.to_s if name.is_a?(Symbol)

        if name.include?('/')
          if name.starts_with?('@')
            # Scoped bare specifier (eg. "@scoped/package/lib/button@default").
            _, path, name = name.split('@')
            path = "@#{path}"
          elsif name.starts_with?('/')
            # Local path with leading slash.
            path, name = name[1..].split('@')
          else
            # Bare specifier (eg. "mypackage/lib/button@default").
            path, name = name.split('@')
          end

          class_name name, path: "#{path}.module.css"
        elsif name.starts_with?('@')
          class_name name[1..]
        else
          require_prefix ? name : class_name(name)
        end
      end
    end

    def class_name(name, path: @source_path)
      resolved_path = Resolver.resolve(path.to_s)
      digest = Importer.import(resolved_path)

      sname = name.to_s
      if sname.starts_with?('_')
        "_#{sname[1..].camelize(:lower)}#{digest}"
      else
        "#{sname.camelize(:lower)}#{digest}"
      end
    end
  end
end
