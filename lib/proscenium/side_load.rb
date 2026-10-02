# frozen_string_literal: true

module Proscenium
  class SideLoad
    JS_COMMENT = '<!-- [PROSCENIUM_JAVASCRIPTS] -->'
    CSS_COMMENT = '<!-- [PROSCENIUM_STYLESHEETS] -->'

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
        fragments = proscenium_fragment_header&.split(/[,\s]+/)

        return if !fragments && !included_comment

        out = []
        Proscenium::Importer.each_stylesheet(delete: true) do |path, opts|
          opts = opts[:css].is_a?(Hash) ? opts[:css] : {}
          opts = opts.merge(data: opts[:data] || {})
          opts = opts.merge(preload_links_header: false) if fragments

          out << helpers.stylesheet_link_tag(path.delete_prefix('/'), extname: false, **opts)
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

        included_comment = response_body.first.include?(JS_COMMENT)
        fragments = proscenium_fragment_header&.split(/[,\s]+/)

        return if !fragments && !included_comment

        out = []
        Proscenium::Importer.each_javascript(delete: true) do |path, opts|
          next if opts.delete(:lazy)

          opts = opts[:js].is_a?(Hash) ? opts[:js] : {}
          opts = opts.merge(preload_links_header: false) if fragments

          out << helpers.javascript_include_tag(path.delete_prefix('/'), extname: false, **opts)
        end

        if fragments
          response_body.first.prepend out.join.html_safe
        elsif included_comment
          response_body.first.gsub! JS_COMMENT, out.join.html_safe
        end
      end

      private

      # Fragment rendering: phlex-rails 1.x used `X-Fragment`, phlex-rails 2.x uses `X-Fragments`.
      # Honour both so side-loaded assets are injected into fragment responses regardless of the
      # phlex-rails version in use. The value is only used as a presence flag (all imported assets
      # are injected — Proscenium does not filter by fragment name), so the split delimiter is
      # cosmetic; splitting on comma or whitespace covers both conventions (plural is comma-based).
      def proscenium_fragment_header
        request.headers['X-Fragment'] || request.headers['X-Fragments']
      end
    end

    class << self
      # Side loads assets for the class, and its super classes that respond to `.source_path`, which
      # should return a Pathname of the class source file.
      #
      # Set the `abstract_class` class variable to true in any class, and it will not be side
      # loaded.
      #
      # If the class responds to `.sideload`, it will be called after the regular side loading. You
      # can use this to customise what is side loaded.
      def sideload_inheritance_chain(obj, options)
        return unless Proscenium.config.side_load

        options = merge_options(options, obj.sideload_assets_options, obj)

        css_imports = []

        klass = obj.class
        while klass.respond_to?(:source_path) && klass.source_path &&
              (klass.respond_to?(:abstract_class) ? !klass.abstract_class : true)
          if options[:css] == false
            Importer.sideload klass.source_path, **options
          else
            Importer.sideload_js klass.source_path, **options
            css_imports << klass.source_path
          end

          klass.sideload options if klass.respond_to?(:sideload)

          klass = klass.superclass
        end

        # All regular CSS files (*.css) are ancestrally sideloaded. However, the first CSS module
        # in the ancestry is also sideloaded in addition to the regular CSS files. This is because
        # the CSS module digest will be different for each file, so we only sideload the first CSS
        # module.
        css_imports.each do |it| # rubocop:disable Style/ItAssignment
          break if Importer.sideload_css_module(it, **options).present?
        end

        # Sideload regular CSS files in reverse order.
        #
        # The reason why we sideload CSS after JS is because the order of CSS is important.
        # Basically, the layout should be loaded before the view so that CSS cascading works in the
        # right direction.
        css_imports.reverse_each do |it| # rubocop:disable Style/ItAssignment
          Importer.sideload_css it, **options
        end
      end

      # Whether `template`, rendered by `view`, should have its assets side loaded.
      def sideloadable?(view, template)
        Proscenium.config.side_load && view.controller.respond_to?(:sideload_assets_options) &&
          template.respond_to?(:identifier) && template.respond_to?(:type) && template.type == :html
      end

      # Renders the block, then side loads each of `templates`, and returns what the block
      # returned. A template's `sideload_assets` value belongs to this one render: the view's
      # stored value is set aside before the block and put back after it, so a repeated or nested
      # render of the same template neither inherits this one's value nor overwrites it.
      def sideload_templates(view, templates)
        # A layout can be `false`, meaning none, and a template can be its own layout.
        templates = templates.select(&:itself).uniq(&:identifier)
        # A view rendered before Proscenium::Helper is included has nowhere to store a value.
        store = view.try(:proscenium_sideload_assets_options) || {}
        saved = templates.to_h { |tpl| [tpl.identifier, store.delete(tpl.identifier)] }

        result = yield
        templates.each { |tpl| sideload_template tpl, view.controller, store[tpl.identifier] }
        result
      ensure
        saved&.each { |id, value| value.nil? ? store.delete(id) : store[id] = value }
      end

      # Returns a new options hash: `base`, with `override` deep merged over it, or replacing it
      # when not a Hash, and any Proc `css`/`js` value evaluated against `receiver`. A nil `base`
      # is empty, and a nil `override` changes nothing. Keys are symbolized at every depth, before
      # merging, so options with indifferent access merge with symbol-keyed ones.
      #
      # Neither input is modified, and no Hash is shared with them - `base` is usually a class
      # attribute, so writing to it would leak one request's options into every later one. Values
      # other than hashes are passed through as they are, not copied: `dup` on an ActiveRecord
      # model returns a new record with no id.
      def merge_options(base, override, receiver)
        options = base.nil? ? {} : base
        options = { js: options, css: options } unless options.is_a?(Hash)
        options = options.deep_symbolize_keys

        unless override.nil?
          options = if override.is_a?(Hash)
                      options.deep_merge(override.deep_symbolize_keys)
                    else
                      { js: override, css: override }
                    end
        end

        options.to_h do |key, value|
          value = receiver.instance_exec(&value) if (key in :css | :js) && value.is_a?(Proc)
          [key, value.is_a?(Hash) ? value.deep_symbolize_keys : value]
        end
      end

      private

      def sideload_template(tpl, controller, override)
        return unless (tpl_path = Pathname.new(tpl.identifier)).file?

        options = merge_options(controller.sideload_assets_options, override, controller)
        Importer.sideload tpl_path, **options
      end
    end
  end
end
