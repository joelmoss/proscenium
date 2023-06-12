# frozen_string_literal: true

#
# Renders a div for use with @proscenium/component-manager.
#
# You can pass props to the component in the `:props` keyword argument.
#
class Proscenium::Phlex::ReactComponent < Proscenium::Phlex
  self.abstract_class = true

  include Proscenium::Phlex::ComponentConcerns::CssModules

  attr_writer :props

  # @param props: [Hash]
  def initialize(props: {}) # rubocop:disable Lint/MissingSuper
    @props = props
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

  def component_data
    { path: virtual_path, props: props.deep_transform_keys { |k| k.to_s.camelize :lower } }.to_json
  end

  def virtual_path
    path.to_s.delete_prefix(Rails.root.to_s).sub(/\.rb$/, '')
  end
end
