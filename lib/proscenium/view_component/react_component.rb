# frozen_string_literal: true

#
# Renders a <div> for use with React components, with data attributes specifying the component path
# and props.
#
# If a content block is given, that content will be rendered inside the component, allowing for a
# "loading" UI. If no block is given, then a "loading..." text will be rendered. It is intended that
# the component is mounted to this div, and the loading UI will then be replaced with the
# component's rendered output.
#
class Proscenium::ViewComponent::ReactComponent < Proscenium::ViewComponent
  self.abstract_class = true

  attr_accessor :props

  # The HTML tag to use as the wrapping element for the component. You can reassign this in your
  # component class to use a different tag:
  #
  #   class MyComponent < Proscenium::ViewComponent::ReactComponent
  #     self.root_tag = :span
  #   end
  #
  # @return [Symbol]
  class_attribute :root_tag, instance_predicate: false, default: :div

  # @param props: [Hash]
  def initialize(props: {})
    @props = props

    super
  end

  def call
    tag.send root_tag, data: {
      proscenium_component_path: path.to_s.delete_prefix(Rails.root.to_s).sub(/\.rb$/, ''),
      proscenium_component_props: props.deep_transform_keys { |k| k.to_s.camelize :lower }.to_json
    } do
      tag.div content || 'loading...'
    end
  end
end
