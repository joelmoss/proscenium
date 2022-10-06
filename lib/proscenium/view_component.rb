# frozen_string_literal: true

module Proscenium::ViewComponent
  extend ActiveSupport::Autoload

  autoload :TagBuilder

  def render_in(view_context, &block)
    Rails.env.test? ? super : parse_content(super)
  end

  def before_render
    side_load_assets unless self.class < ReactComponent
  end

  def css_module(name)
    cssm.class_names(name.to_s.camelize(:lower)).join ' '
  end

  private

  # Side load any CSS/JS assets for the component. This will side load any `index.{css|js}` in
  # the component directory.
  def side_load_assets
    Proscenium::SideLoad.append asset_path if Rails.application.config.proscenium.side_load
  end

  def asset_path
    @asset_path ||= "app/components#{virtual_path}"
  end

  def cssm
    @cssm ||= Proscenium::CssModule.new(asset_path)
  end

  # Overrides ActionView::Helpers::TagHelper::TagBuilder, allowing us to intercept the
  # `css_module` option from the HTML options argument of the `tag` and `content_tag` helpers, and
  # prepend it to the HTML `class` attribute.
  def tag_builder
    @tag_builder ||= Proscenium::ViewComponent::TagBuilder.new(self)
  end

  # Parses the given `content` for CSS modules names ('class' attributes beginning with '@'), and
  # returns the content with said CSS Modules replaced with the compiled class names.
  #
  # Example:
  #   <div class="@my_css_module_name"></div>
  def parse_content(content)
    doc = Nokogiri::HTML::DocumentFragment.parse(content)

    return content if (modules = doc.css('[class*="@"]')).empty?

    modules.each do |ele|
      classes = ele.classes.map { |cls| cls.starts_with?('@') ? css_module(cls[1..]) : cls }
      ele['class'] = classes.join(' ')
    end

    doc.to_html.html_safe
  end
end
