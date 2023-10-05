# frozen_string_literal: true

module Proscenium
  module Helper
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
    def css_module(*names)
      path = Pathname.new(@lookup_context.find(@virtual_path).identifier).sub_ext('')
      CssModule::Transformer.new(path).class_names(*names, require_prefix: false).map do |name, _|
        name
      end.join(' ')
    end

    def include_stylesheets(**options)
      out = []
      Importer.each_stylesheet(delete: true) do |path, _path_options|
        out << stylesheet_link_tag(path, extname: false, **options)
      end
      out.join("\n").html_safe
    end
    alias side_load_stylesheets include_stylesheets
    deprecate side_load_stylesheets: 'Use `include_stylesheets` instead', deprecator: Deprecator.new

    # Includes all javascripts that have been imported and side loaded.
    #
    # @param extract_lazy_scripts [Boolean] if true, any lazy scripts will be extracted using
    #   `content_for` to `:proscenium_lazy_scripts` for later use. Be sure to include this in your
    #   page with the `declare_lazy_scripts` helper, or simply
    #   `content_for :proscenium_lazy_scripts`.
    # @return [String] the HTML tags for the javascripts.
    def include_javascripts(extract_lazy_scripts: false, **options) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      out = []

      if Rails.application.config.proscenium.code_splitting && Importer.multiple_js_imported?
        imports = Importer.imported.dup

        paths_to_build = []
        Importer.each_javascript(delete: true) do |x, _|
          paths_to_build << x.delete_prefix('/')
        end

        result = Builder.build(paths_to_build.join(';'), base_url: request.base_url)

        # Remove the react components from the results, so they are not side loaded. Instead they
        # are lazy loaded by the component manager.

        scripts = {}
        result.split(';').each do |x|
          inpath, outpath = x.split('::')
          inpath.prepend '/'
          outpath.delete_prefix! 'public'

          next unless imports.key?(inpath)

          if (import = imports[inpath]).delete(:lazy)
            scripts[inpath] = import.merge(outpath: outpath)
          else
            out << javascript_include_tag(outpath, extname: false, **options)
          end
        end

        if extract_lazy_scripts
          content_for :proscenium_lazy_scripts do
            javascript_tag "window.prosceniumLazyScripts = #{scripts.to_json}"
          end
        else
          out << javascript_tag("window.prosceniumLazyScripts = #{scripts.to_json}")
        end
      else
        Importer.each_javascript(delete: true) do |path, _|
          out << javascript_include_tag(path, extname: false, **options)
        end
      end

      out.join("\n").html_safe
    end
    alias side_load_javascripts include_javascripts
    deprecate side_load_javascripts: 'Use `include_javascripts` instead', deprecator: Deprecator.new

    def declare_lazy_scripts
      content_for :proscenium_lazy_scripts
    end
  end
end
