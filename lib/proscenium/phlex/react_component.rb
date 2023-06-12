# frozen_string_literal: true

#
# Renders a <div> for use with React components, with data attributes specifying the component path
# and props.
#
# If a block is given, it will be yielded within the div, allowing for a custom "loading" UI. If no
# block is given, then a "loading..." text will be rendered. It is intended that the component is
# mounted to this div, and the loading UI will then be replaced with the component's rendered
# output.
#
# You can pass props to the component in the `:props` keyword argument.
#
class Proscenium::Phlex::ReactComponent < Proscenium::Phlex
  self.abstract_class = true

  include Proscenium::Phlex::ComponentConcerns::CssModules

  attr_writer :props

  # The HTML tag to use as the wrapping element for the component. You can reassign this in your
  # component class to use a different tag:
  #
  #   class MyComponent < Proscenium::Phlex::ReactComponent
  #     self.root_tag = :span
  #   end
  #
  # @return [Symbol]
  class_attribute :root_tag, instance_predicate: false, default: :div

  # @param props: [Hash]
  def initialize(props: {}) # rubocop:disable Lint/MissingSuper
    @props = props
  end

  # Override this to provide your own loading UI.
  #
  # Example:
  #
  #   def template(**attributes, &block)
  #     super do
  #       'Look at me! I am loading now...'
  #     end
  #   end
  #
  # @yield the given block to a `div` within the top level component div. If not given,
  #   `<div>loading...</div>` will be rendered. Use this to display a loading UI while the component
  #   is loading and rendered.
  def template(**attributes, &block)
    send root_tag, data: {
      proscenium_component_path: virtual_path,
      proscenium_component_props: props.deep_transform_keys { |k| k.to_s.camelize :lower }.to_json
    }, **attributes do
      block ? yield : 'loading...'
    end
  end

  private

  def props
    @props ||= {}
  end

  def virtual_path
    path.to_s.delete_prefix(Rails.root.to_s).sub(/\.rb$/, '')
  end
end
