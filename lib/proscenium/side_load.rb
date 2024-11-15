# frozen_string_literal: true

module Proscenium
  class SideLoad
    JS_COMMENT = '<!-- [PROSCENIUM_JAVASCRIPTS] -->'
    CSS_COMMENT = '<!-- [PROSCENIUM_STYLESHEETS] -->'
    LAZY_COMMENT = '<!-- [PROSCENIUM_LAZY_SCRIPTS] -->'

    module Controller
      def self.included(child)
        child.class_eval do
          class_attribute :sideload_assets_options
          child.extend ClassMethods

          append_after_action :capture_and_replace_proscenium_stylesheets,
                              :capture_and_replace_proscenium_javascripts,
                              if: -> { response.content_type&.include?('html') }
        end
      end

      module ClassMethods
        def sideload_assets(value)
          self.sideload_assets_options = value
        end
      end

      def capture_and_replace_proscenium_stylesheets
        return if response_body.nil?
        return if response_body.first.blank? || !Proscenium::Importer.css_imported?

        included_comment = response_body.first.include?(CSS_COMMENT)
        fragments = if (fragment_header = request.headers['X-Fragment'])
                      fragment_header.split
                    end

        return if !fragments && !included_comment

        imports = Proscenium::Importer.imported.dup
        paths_to_build = []
        Proscenium::Importer.each_stylesheet(delete: true) do |x, _|
          paths_to_build << x.delete_prefix('/')
        end

        result = Proscenium::Builder.build_to_path(paths_to_build.join(';'),
                                                   base_url: helpers.request.base_url)

        out = []
        result.split(';').each do |x|
          inpath, outpath = x.split('::')
          inpath.prepend '/'
          outpath.delete_prefix! 'public'

          next unless imports.key?(inpath)

          import = imports[inpath]
          opts = import[:css].is_a?(Hash) ? import[:css] : {}
          opts[:preload_links_header] = false if fragments
          opts[:data] ||= {}
          opts[:data][:original_href] = inpath
          out << helpers.stylesheet_link_tag(outpath, extname: false, **opts)
        end

        if fragments
          response_body.first.prepend out.join.html_safe
        elsif included_comment
          response_body.first.gsub! CSS_COMMENT, out.join.html_safe
        end
      end

      def capture_and_replace_proscenium_javascripts
        return if response_body.nil?
        return if response_body.first.blank? || !Proscenium::Importer.js_imported?

        imports = Proscenium::Importer.imported.dup
        paths_to_build = []
        Proscenium::Importer.each_javascript(delete: true) do |x, _|
          paths_to_build << x.delete_prefix('/')
        end

        result = Proscenium::Builder.build_to_path(paths_to_build.join(';'),
                                                   base_url: helpers.request.base_url)

        included_js_comment = response_body.first.include?(JS_COMMENT)
        included_lazy_comment = response_body.first.include?(LAZY_COMMENT)
        fragments = if (fragment_header = request.headers['X-Fragment'])
                      fragment_header.split
                    end

        if fragments || included_js_comment
          out = []
          scripts = {}
          result.split(';').each do |x|
            inpath, outpath = x.split('::')
            inpath.prepend '/'
            outpath.delete_prefix! 'public'

            next unless imports.key?(inpath)

            if (import = imports[inpath]).delete(:lazy)
              scripts[inpath] = import.merge(outpath:)
            else
              opts = import[:js].is_a?(Hash) ? import[:js] : {}
              opts[:preload_links_header] = false if fragments
              out << helpers.javascript_include_tag(outpath, extname: false, **opts)
            end
          end

          if fragments
            response_body.first.prepend out.join.html_safe
          elsif included_js_comment
            response_body.first.gsub! JS_COMMENT, out.join.html_safe
          end
        end

        return if !fragments && !included_lazy_comment

        lazy_script = ''
        if scripts.present?
          lazy_script = helpers.content_tag 'script', type: 'application/json',
                                                      id: 'prosceniumLazyScripts' do
            scripts.to_json.html_safe
          end
        end

        if fragments
          response_body.first.prepend lazy_script
        elsif included_lazy_comment
          response_body.first.gsub! LAZY_COMMENT, lazy_script
        end
      end
    end

    class << self
      # Side loads the class, and its super classes that respond to `.source_path`.
      #
      # Set the `abstract_class` class variable to true in any class, and it will not be side
      # loaded.
      #
      # If the class responds to `.sideload`, it will be called instead of the regular side loading.
      # You can use this to customise what is side loaded.
      def sideload_inheritance_chain(obj, options)
        return unless Proscenium.config.side_load

        options = {} if options.nil?
        options = { js: options, css: options } unless options.is_a?(Hash)

        unless obj.sideload_assets_options.nil?
          tpl_options = obj.sideload_assets_options
          options = if tpl_options.is_a?(Hash)
                      options.deep_merge tpl_options
                    else
                      { js: tpl_options, css: tpl_options }
                    end
        end

        %i[css js].each do |k|
          options[k] = obj.instance_eval(&options[k]) if options[k].is_a?(Proc)
        end

        css_imports = []

        klass = obj.class
        while klass.respond_to?(:source_path) && klass.source_path && !klass.abstract_class
          if klass.respond_to?(:sideload)
            klass.sideload options
          elsif options[:css] == false
            Importer.sideload klass.source_path, **options
          else
            Importer.sideload_js klass.source_path, **options
            css_imports << klass.source_path
          end

          klass = klass.superclass
        end

        # The reason why we sideload CSS after JS is because the order of CSS is important.
        # Basically, the layout should be loaded before the view so that CSS cascading works i9n the
        # right direction.
        css_imports.reverse_each do |it|
          Importer.sideload_css it, **options
        end
      end
    end
  end
end
