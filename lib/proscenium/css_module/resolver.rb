# frozen_string_literal: true

module Proscenium
  class CssModule::Resolver
    attr_reader :side_loaded_paths

    # @param path [Pathname] Absolute file system path to the Ruby file that will be side loaded.
    def initialize(path, side_load: true, hash: nil)
      raise ArgumentError, "'#{path}' must be a `Pathname`" unless path.is_a?(Pathname)

      @path = path
      @hash = hash
      @css_module_path = path.sub_ext('.module.css')
      @side_load = side_load
      @side_loaded_paths = nil
    end

    # Parses the given `content` for CSS modules names ('class' attributes beginning with '@'), and
    # returns the content with said CSS Modules replaced with the compiled class names.
    #
    # Example:
    #   <div class="@my_css_module_name"></div>
    def compile_class_names(content)
      doc = Nokogiri::HTML::DocumentFragment.parse(content)

      return content if (modules = doc.css('[class*="@"]')).empty?

      modules.each do |ele|
        classes = ele.classes.map { |cls| cls.starts_with?('@') ? class_names!(cls[1..]) : cls }
        ele['class'] = classes.join(' ')
      end

      doc.to_html.html_safe
    end

    # Resolves the given CSS class names to CSS modules. This will also side load the stylesheet if
    # it exists.
    #
    # @param names [String, Array]
    # @returns [Array] of class names generated from the given CSS module `names`.
    def class_names(*names)
      side_load_css_module
      Utils.css_modularise_class_names names, digest: @hash
    end

    # Like #class_names, but requires that the stylesheet exists.
    #
    # @param names [String, Array]
    # @raises Proscenium::CssModule::NotFound if stylesheet does not exists.
    # @see #class_names
    def class_names!(...)
      raise StylesheetNotFound, @css_module_path unless @css_module_path.exist?

      class_names(...)
    end

    def side_loaded?
      @side_loaded_paths.present?
    end

    private

    def side_load_css_module
      return if !@side_load || !Rails.application.config.proscenium.side_load

      paths = SideLoad.append @path, { '.module.css' => :css }

      @side_loaded_paths = if paths.empty?
                             nil
                           else
                             @hash = Utils.digest(paths[0])
                             paths
                           end
    end
  end
end
