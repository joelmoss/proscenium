# frozen_string_literal: true

module Proscenium
  module Helper
    def sideload_assets(value)
      if value.nil?
        @current_template.instance_variable_defined?(:@sideload_assets_options) &&
          @current_template.remove_instance_variable(:@sideload_assets_options)
      else
        @current_template.instance_variable_set :@sideload_assets_options, value
      end
    end

    def compute_asset_path(path, options = {})
      if %i[javascript stylesheet].include?(options[:type])
        result = "/#{path}"

        if (qs = Proscenium.config.cache_query_string)
          result << "?#{qs}"
        end

        return result
      end

      super
    end

    # Accepts one or more CSS class names, and transforms them into CSS module names.
    #
    # @see CssModule::Transformer#class_names
    # @param name [String,Symbol,Array<String,Symbol>]
    # @param path [Pathname] the path to the CSS module file to use for the transformation.
    # @return [String] the transformed CSS module names concatenated as a string.
    def css_module(*names, path: nil)
      path ||= Pathname.new(@lookup_context.find(@virtual_path).identifier).sub_ext('')
      CssModule::Transformer.new(path).class_names(*names, require_prefix: false)
                            .map { |name, _| name }.join(' ')
    end

    # @param name [String,Symbol,Array<String,Symbol>]
    # @param path [Pathname] the path to the CSS file to use for the transformation.
    # @return [String] the transformed CSS module names concatenated as a string.
    def class_names(*names, path: nil)
      names = names.flatten.compact

      return if names.empty?

      path ||= Pathname.new(@lookup_context.find(@virtual_path).identifier).sub_ext('')
      CssModule::Transformer.new(path).class_names(*names).map { |name, _| name }.join(' ')
    end

    def include_assets
      include_stylesheets + include_javascripts
    end

    def include_stylesheets
      '<!-- [PROSCENIUM_STYLESHEETS] -->'.html_safe
    end
    alias side_load_stylesheets include_stylesheets
    deprecate side_load_stylesheets: 'Use `include_stylesheets` instead', deprecator: Deprecator.new

    # Includes all javascripts that have been imported and side loaded.
    #
    # @return [String] the HTML tags for the javascripts.
    def include_javascripts
      '<!-- [PROSCENIUM_LAZY_SCRIPTS] --><!-- [PROSCENIUM_JAVASCRIPTS] -->'.html_safe
    end
    alias side_load_javascripts include_javascripts
    deprecate side_load_javascripts: 'Use `include_javascripts` instead', deprecator: Deprecator.new
  end
end
