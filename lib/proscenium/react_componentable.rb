# frozen_string_literal: true

module Proscenium::ReactComponentable
  extend ActiveSupport::Concern

  included do
    # @return [Hash] the props to pass to the React component.
    attr_writer :props

    # The HTML tag to use as the wrapping element for the component. You can reassign this in your
    # component class to use a different tag:
    #
    #   class MyComponent < Proscenium::ViewComponent::ReactComponent
    #     self.root_tag = :span
    #   end
    #
    # @return [Symbol]
    class_attribute :root_tag, instance_predicate: false, default: :div

    # Should the template block be forwarded as children to the React component?
    #
    # @return [Boolean]
    class_attribute :forward_children, default: false

    # Lazy load the component using IntersectionObserver?
    #
    # @return [Boolean]
    class_attribute :lazy, default: false
  end

  class_methods do
    def sideload
      # Import the component manager.
      Proscenium::Importer.import '/lib/manager/index.jsx'
      Proscenium::Importer.sideload path, lazy: true
    end
  end

  # @param props: [Hash]
  def initialize(props: {})
    @props = props

    super()
  end

  def virtual_path
    Proscenium::Utils.resolve_path path.sub_ext('.jsx').to_s
  end

  private

  def data_attributes
    d = {
      proscenium_component_path: Pathname.new(virtual_path).to_s,
      proscenium_component_props: prepared_props,
      proscenium_component_lazy: lazy
    }

    d[:proscenium_component_forward_children] = true if forward_children?

    d
  end

  def props
    @props ||= {}
  end

  def prepared_props
    props.deep_transform_keys do |term|
      # This ensures that the first letter after a slash is not capitalized.
      string = term.to_s.split('/').map { |str| str.camelize :lower }.join('/')

      # Reverses the effect of ActiveSupport::Inflector.camelize converting slashes into `::`.
      string.gsub '::', '/'
    end.to_json
  end
end
