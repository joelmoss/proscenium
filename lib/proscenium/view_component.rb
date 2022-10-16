# frozen_string_literal: true

module Proscenium::ViewComponent
  extend ActiveSupport::Autoload

  autoload :TagBuilder

  def render_in(...)
    cssm.compile_class_names(super)
  end

  def before_render
    side_load_assets unless self.class < ReactComponent
  end

  def css_module(name)
    cssm.class_names!(name).join ' '
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
end
