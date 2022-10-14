# frozen_string_literal: true

class Proscenium::CssModule
  def initialize(path)
    @path = "#{path}.module.css"

    return unless Rails.application.config.proscenium.side_load

    Proscenium::SideLoad.append! Rails.root.join(@path)
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

  # Returns an Array of class names generated from the given CSS module `names`.
  def class_names(*names)
    names.flatten.compact.map { |name| "#{name.to_s.camelize(:lower)}#{hash}" }
  end

  private

  def hash
    @hash ||= Digest::SHA1.hexdigest("/#{@path}")[..7]
  end
end
