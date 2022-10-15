# frozen_string_literal: true

class Proscenium::CssModule
  class NotFound < StandardError
    def initialize(pathname)
      @pathname = pathname
      super
    end

    def message
      "Stylesheet is required, but does not exist: #{@pathname}"
    end
  end

  def initialize(path)
    @path = "#{path}.module.css"

    return unless Rails.application.config.proscenium.side_load

    Proscenium::SideLoad.append "#{path}.module", :css
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
      classes = ele.classes.map { |cls| cls.starts_with?('@') ? class_names(cls[1..]) : cls }
      ele['class'] = classes.join(' ')
    end

    doc.to_html.html_safe
  end

  # @returns [Array] of class names generated from the given CSS module `names`.
  def class_names(*names)
    names.flatten.compact.map { |name| "#{name.to_s.camelize(:lower)}#{hash}" }
  end

  # Like #class_names, but requires that the stylesheet exists.
  #
  # @raises Proscenium::CssModule::NotFound if stylesheet does not exists.
  def class_names!(...)
    raise NotFound, @path unless Rails.root.join(@path).exist?

    class_names(...)
  end

  private

  def hash
    @hash ||= Digest::SHA1.hexdigest("/#{@path}")[..7]
  end
end
