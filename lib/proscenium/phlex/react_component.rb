# frozen_string_literal: true

#
# Renders a div for use with component-manager.
#
class Proscenium::Phlex::ReactComponent < Proscenium::Phlex::Component
  attr_accessor :props, :lazy

  # @param props: [Hash]
  # @param lazy: [Boolean] Lazy load the component using IntersectionObserver. Default: true.
  def initialize(props: {}, lazy: true) # rubocop:disable Lint/MissingSuper
    @props = props
    @lazy = lazy
  end

  # @yield the given block to a `div` within the top level component div. If not given,
  #   `<div>loading...</div>` will be rendered. Use this to display a loading UI while the component
  #   is loading and rendered.
  def template(&block)
    div class: ['componentManagedByProscenium', '@component'],
        data: { component: { path: virtual_path, props: props, lazy: lazy }.to_json } do
      block ? div(&block) : div { 'loading...' }
    end
  end
end
