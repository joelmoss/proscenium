# frozen_string_literal: true

#
# Renders a div for use with @proscenium/component-manager.
#
# You can pass props to the component in the `:props` keyword argument.
#
# By default, the component is lazy loaded when intersecting using IntersectionObserver. Pass in
# :lazy as false to disable this and render the component immediately.
#
# React components are not side loaded at all.
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

  include Proscenium::CssModule
  include Proscenium::Phlex::ResolveCssModules

  attr_writer :props, :lazy

  # @param props: [Hash]
  # @param lazy: [Boolean] Lazy load the component using IntersectionObserver. Default: true.
  def initialize(props: {}, lazy: true) # rubocop:disable Lint/MissingSuper
    @props = props
    @lazy = lazy
  end

  # @yield the given block to a `div` within the top level component div. If not given,
  #   `<div>loading...</div>` will be rendered. Use this to display a loading UI while the component
  #   is loading and rendered.
  def template(**attributes, &block)
    component_root(:div, **attributes, &block)
  end

  private

  def component_root(element, **attributes, &block)
    send element, data: { proscenium_component: component_data }, **attributes, &block
  end

  def props
    @props ||= {}
  end

  def lazy
    instance_variable_defined?(:@lazy) ? @lazy : (@lazy = false)
  end

  def component_data
    {
      path: virtual_path, lazy: lazy,
      props: props.deep_transform_keys { |k| k.to_s.camelize :lower }
    }.to_json
  end

  def virtual_path
    path.to_s.delete_prefix(Rails.root.to_s)
  end
end
