# frozen_string_literal: true

module Proscenium::UI::Breadcrumbs
  # Include this module in your controller to add support for adding breadcrumb elements. You can
  # then use the `add_breadcrumb` and `prepend_breadcrumb` class methods to append and/or prepend
  # breadcrumb elements.
  module Control
    extend ActiveSupport::Concern
    include ActionView::Helpers::SanitizeHelper

    included do
      helper_method :breadcrumbs_as_json, :breadcrumbs_for_title if respond_to?(:helper_method)
    end

    module ClassMethods
      # Appends a new breadcrumb element into the collection.
      #
      # @param name [String, Symbol, Proc, #for_breadcrumb] The name or content of the breadcrumb.
      # @param path [String, Symbol, Array, Proc, nil] The path (route) to use as the HREF for the
      #   breadcrumb.
      # @param filter_options [Hash] Options to pass through to the before_action filter.
      def add_breadcrumb(name, path = nil, **filter_options)
        element_options = filter_options.delete(:options) || {}

        before_action(filter_options) do |controller|
          controller.send :add_breadcrumb, name, path, element_options
        end
      end

      # Prepend a new breadcrumb element into the collection.
      #
      # @param name [String, Symbol, Proc, #for_breadcrumb] The name or content of the breadcrumb.
      # @param path [String, Symbol, Array, Proc, nil] The path (route) to use as the HREF for the
      #   breadcrumb.
      # @param filter_options [Hash] Options to pass through to the before_action filter.
      def prepend_breadcrumb(name, path = nil, **filter_options)
        element_options = filter_options.delete(:options) || {}

        before_action(filter_options) do |controller|
          controller.send :prepend_breadcrumb, name, path, element_options
        end
      end
    end

    # Pushes a new breadcrumb element into the collection.
    #
    # @param name [String, Symbol, Proc, #for_breadcrumb] The name or content of the breadcrumb.
    # @param path [String, Symbol, Array, Proc, nil] The path (route) to use as the HREF for the
    #   breadcrumb.
    # @param options [Hash]
    def add_breadcrumb(name, path = nil, options = {})
      breadcrumbs << Element.new(name, path, options)
    end

    # Prepend a new breadcrumb element into the collection.
    #
    # @param name [String, Symbol, Proc, #for_breadcrumb] The name or content of the breadcrumb.
    # @param path [String, Symbol, Array, Proc, nil] The path (route) to use as the HREF for the
    #   breadcrumb.
    # @param options [Hash]
    def prepend_breadcrumb(name, path = nil, options = {})
      breadcrumbs.prepend Element.new(name, path, options)
    end

    def breadcrumbs
      @breadcrumbs ||= []
    end

    def breadcrumbs_as_json
      computed_breadcrumbs.map do |ele|
        path = ele.path

        { name: ele.name, path: ele.path.nil? || helpers.current_page?(path) ? nil : path }
      end
    end

    def breadcrumbs_for_title
      @breadcrumbs_for_title ||= begin
        names = computed_breadcrumbs.map(&:name)
        out = [names.pop]
        out << names.join(': ') unless names.empty?
        strip_tags out.join(' - ')
      end
    end

    private

    def computed_breadcrumbs
      @computed_breadcrumbs ||= breadcrumbs.map do |ele|
        ComputedElement.new ele, helpers
      end
    end
  end
end
