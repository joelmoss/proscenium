# frozen_string_literal: true

class Proscenium::CssModule::Resolver
  class NotFound < StandardError
    def initialize(pathname)
      @pathname = pathname
      super
    end

    def message
      "Stylesheet is required, but does not exist: #{@pathname}"
    end
  end

  def initialize(path, side_load: true, hash: nil)
    raise ArgumentError, "'#{path}' must be a `Pathname`" unless path.is_a?(Pathname)

    @path = path
    @hash = hash
    @css_module_path = path.sub_ext('.module.css')
    @side_load = side_load
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

  # Resolves the given CSS class names to CSS modules. This will also side load the stylesheet if it
  # exists.
  #
  # @param names [String, Array]
  # @returns [Array] of class names generated from the given CSS module `names`.
  def class_names(*names)
    side_load_css_module
    Proscenium::Utils.class_names(names, hash: hash)
  end

  # Like #class_names, but requires that the stylesheet exists.
  #
  # @param names [String, Array]
  # @raises Proscenium::CssModule::NotFound if stylesheet does not exists.
  # @see #class_names
  def class_names!(...)
    raise NotFound, @css_module_path unless @css_module_path.exist?

    class_names(...)
  end

  private

  def hash
    @hash ||= Proscenium::Utils.digest(@css_module_path)
  end

  def side_load_css_module
    return if !@side_load || !Rails.application.config.proscenium.side_load

    paths = Proscenium::SideLoad.append @path, { '.module.css' => :css }
    @hash = Proscenium::Utils.digest(paths[0])
  end
end
