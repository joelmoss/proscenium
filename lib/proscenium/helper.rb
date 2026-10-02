# frozen_string_literal: true

module Proscenium
  module Helper
    # Sets the side load options of the template being rendered, for this render only. They are
    # kept on the view, which lives for one request, keyed by template, because the template
    # object itself is cached and shared by every request. `SideLoad.sideload_templates` scopes
    # each value to the render that set it.
    #
    # Call it outside any `cache` block: a cache hit skips the block, and this call with it.
    def sideload_assets(value)
      # ActionView does not push a partial rendered with a block onto `@current_template`, so while
      # its body renders, `@current_template` is still the calling template.
      identifier = (@proscenium_block_partial || @current_template).identifier

      if value.nil?
        proscenium_sideload_assets_options.delete identifier
      else
        proscenium_sideload_assets_options[identifier] = value
      end
    end

    # Renders a partial given `block`, and yields the block to render it with. While the partial's
    # body renders, `sideload_assets` applies to the partial. While the block runs, wherever it is
    # run from, it applies to the template that passed the block. Any template rendered from
    # either pushes itself onto `@current_template`, and `Monkey::Base` clears this while it does.
    def proscenium_render_block_partial(partial, block)
      previous = @proscenium_block_partial
      calling_template = previous || @current_template
      @proscenium_block_partial = partial

      yield(proc do |*args|
        current = @proscenium_block_partial
        @proscenium_block_partial = calling_template
        block.call(*args)
      ensure
        @proscenium_block_partial = current
      end)
    ensure
      @proscenium_block_partial = previous
    end

    # @return [Hash] the `sideload_assets` value of each template in this render, by identifier.
    def proscenium_sideload_assets_options
      @proscenium_sideload_assets_options ||= {}
    end

    def compute_asset_path(path, options = {})
      if %i[javascript stylesheet].include?(options[:type])
        return Proscenium::Manifest[path] || "/#{path}"
      end

      super
    end

    # Accepts one or more CSS class names, and transforms them into CSS module names.
    #
    # @see CssModule::Transformer#class_names
    # @param names [String,Symbol,nil,false,Array<String,Symbol,nil,false>]
    # @param path [Pathname] the path to the CSS module file to use for the transformation.
    # @return [String] the transformed CSS module names concatenated as a string.
    def css_module(*names, path: nil)
      path ||= Pathname.new(@lookup_context.find(@virtual_path).identifier).sub_ext('')
      CssModule::Transformer.new(path).class_names(*names, require_prefix: false).join(' ')
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
