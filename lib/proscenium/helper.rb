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

    # Overriden to allow regular use of javascript_include_tag and stylesheet_link_tag, while still
    # building with Proscenium. It's important to note that `include_assets` will not call this, as
    # those asset paths all begin with a slash, which the Rails asset helpers do not pass through to
    # here.
    #
    # If the given `path` is a bare path (does not start with `./` or `../`), then we use
    # Rails default conventions, and serve CSS from /app/assets/stylesheets and JS from
    # /app/javascript.
    def compute_asset_path(path, options = {})
      if %i[javascript stylesheet].include?(options[:type])
        path.prepend DEFAULT_RAILS_ASSET_PATHS[options[:type]] if !path.start_with?('./', '../')
        return path
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

    def include_assets
      include_stylesheets + include_javascripts
    end

    def include_stylesheets
      SideLoad::CSS_COMMENT.html_safe
    end

    # Includes all javascripts that have been imported and side loaded.
    #
    # @return [String] the HTML tags for the javascripts.
    def include_javascripts
      SideLoad::JS_COMMENT.html_safe
    end
  end
end
