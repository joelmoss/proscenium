# frozen_string_literal: true

require 'view_component'

class Proscenium::ViewComponent < ViewComponent::Base
  extend ActiveSupport::Autoload
  include Proscenium::CssModule

  autoload :TagBuilder
  autoload :ReactComponent

  class << self
    attr_accessor :path

    def inherited(child)
      child.path = Pathname.new(caller_locations(1, 1)[0].path)
      super
    end
  end

  def render_in(...)
    cssm.compile_class_names(super(...))
  end

  def before_render
    side_load_assets unless self.class < ReactComponent
  end

  private

  # Side load any CSS/JS assets for the component. This will side load any `index.{css|js}` in
  # the component directory.
  def side_load_assets
    Proscenium::SideLoad.append path if Rails.application.config.proscenium.side_load
  end

  # Overrides ActionView::Helpers::TagHelper::TagBuilder, allowing us to intercept the
  # `css_module` option from the HTML options argument of the `tag` and `content_tag` helpers, and
  # prepend it to the HTML `class` attribute.
  def tag_builder
    @tag_builder ||= Proscenium::ViewComponent::TagBuilder.new(self)
  end
end
