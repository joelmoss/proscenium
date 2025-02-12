# frozen_string_literal: true

module Proscenium
  module ReactComponentable
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

      # By default, the template block (content) of the component will be server rendered as normal.
      # However, when React hydrates and takes control of the component, it's content will be
      # replaced by React with the JavaScript rendered content. Enabling this option will forward
      # the server rendered content as the `children` prop passed to the React component.
      #
      # @example
      #
      #   const Component = ({ children }) => {
      #     return <div dangerouslySetInnerHTML={{ __html: children }} />
      #   }
      #
      # @return [Boolean]
      class_attribute :forward_children, default: false

      # Lazy load the component using IntersectionObserver?
      #
      # @return [Boolean]
      class_attribute :lazy, default: false

      class_attribute :loader

      # @return [String] the URL path to the component manager.
      class_attribute :manager, default: '/proscenium/react-manager/index.jsx'
    end

    class_methods do
      def sideload(options)
        Importer.import manager, **options, js: { type: 'module' }
        Importer.sideload source_path, lazy: true, **options
      end
    end

    # @param props: [Hash]
    def initialize(lazy: self.class.lazy, loader: self.class.loader, props: {})
      self.lazy = lazy
      self.loader = loader
      @props = props
    end

    # The absolute URL path to the javascript component.
    def virtual_path
      @virtual_path ||= Resolver.resolve self.class.source_path.sub_ext('.jsx').to_s
    end

    def props
      @props ||= {}
    end

    private

    def data_attributes
      {
        proscenium_component_path: Pathname.new(virtual_path).to_s,
        proscenium_component_props: prepared_props,
        proscenium_component_lazy: lazy
      }.tap do |x|
        x[:proscenium_component_forward_children] = true if forward_children?
      end
    end

    def prepared_props
      props.deep_transform_keys do |term|
        # This ensures that the first letter after a slash is not capitalized.
        string = term.to_s.split('/').map { |str| str.camelize :lower }.join('/')

        # Reverses the effect of ActiveSupport::Inflector.camelize converting slashes into `::`.
        string.gsub '::', '/'
      end.to_json
    end

    def loader_component
      render Loader::Component.new(loader, @html_class, data_attributes, tag: @html_tag)
    end
  end
end
