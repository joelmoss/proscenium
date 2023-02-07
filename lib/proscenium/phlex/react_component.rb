# frozen_string_literal: true

#
# Renders a div for use with @proscenium/component-manager.
#
class Proscenium::Phlex::ReactComponent < Phlex::HTML
  class << self
    attr_accessor :path, :abstract_class

    def inherited(child)
      position = caller_locations(1, 1).first.label == 'inherited' ? 2 : 1
      child.path = Pathname.new caller_locations(position, 1).first.path.sub(/\.rb$/, '')

      super
    end
  end

  self.abstract_class = true

  include Proscenium::Phlex::ResolveCssModules
  include Proscenium::CssModule

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
    div class: ['componentManagedByProscenium', :@component],
        data: { component: { path: virtual_path, props: props, lazy: lazy }.to_json } do
      block ? div(&block) : div { 'loading...' }
    end
  end

  private

  def virtual_path
    path.to_s.delete_prefix(Rails.root.to_s)
  end
end
