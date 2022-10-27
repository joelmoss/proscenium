# frozen_string_literal: true

class Proscenium::ViewComponent::ReactComponent < Proscenium::ViewComponent
  attr_accessor :props, :lazy

  # @param props: [Hash]
  # @param lazy: [Boolean] Lazy load the component using IntersectionObserver. Default: true.
  def initialize(props: {}, lazy: true)
    @props = props
    @lazy = lazy

    super
  end

  def call
    tag.div class: ['componentManagedByProscenium', css_module(:component)],
            data: { component: { path: virtual_path, props: props, lazy: lazy } } do
      tag.div content || 'loading...'
    end
  end
end
