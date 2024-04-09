# frozen_string_literal: true

module Proscenium::UI
  module Form::Fields
    #
    # Abstract class to provide basic rendering of an <input>. All field classes inherit this.
    #
    class Base < Component
      attr_reader :attribute, :model, :form, :attributes

      register_element :pui_field

      # In most cases we want to use the main form component stylesheet. Override this method if
      # you want to use a different stylesheet.
      def self.css_module_path
        source_path.join('../../component.module.css')
      end

      # @param attribute [Array]
      # @param model [*]
      # @param form [Proscenium::UI::Form::Component]
      # @param type [Symbol] input type, eg. 'text', 'select'
      # @param error [ActiveModel::Error, String] error message for the attribute.
      # @param attributes [Hash] HTML attributes to pass to the input.
      def initialize(attribute, model, form, type: nil, error: nil, **attributes) # rubocop:disable Lint/MissingSuper,Metrics/ParameterLists
        if attribute.count > 2
          raise ArgumentError, 'attribute cannot be nested more than 2 levels deep'
        end

        @attribute = attribute
        @model = model
        @form = form
        @field_type = type
        @error = error
        @attributes = attributes
      end

      private

      # @return [String] The error message for the attribute.
      def error_message
        @error_message ||= case @error
                           when ActiveModel::Error
                             @error.message
                           when String
                             @error
                           else
                             if model.errors.include?(attribute.join('.'))
                               model.errors.where(attribute.join('.')).first&.message
                             elsif model.errors.include?(attribute.first)
                               model.errors.where(attribute.first).first&.message
                             end
                           end
      end

      def error?
        error_message.present?
      end

      # The main wrapper for the field. This is where the label, input, and error message are
      # rendered. You can override this method to modify the markup of the field.
      #
      # @param tag_name: [Symbol] HTML tag name to use for the wrapper.
      # @param ** [Hash] Additional HTML attributes to pass to the wrapper.
      # @param [Proc] The block to render the field.
      def field(tag_name = :pui_field, **rest, &)
        classes = []
        classes << rest.delete(:class) if rest.key?(:class)
        classes << attributes.delete(:class) if attributes.key?(:class)

        send(tag_name, class: classes, data: { field_error: error? }, **rest, &)
      end

      # Builds the template for the label, along with any error message for the attribute.
      #
      # By default, the translated attribute name will be used as the content for the label. You can
      # overide this by providing the `:label` keyword argument in `@arguments`. Passing false as
      # the value to `:label` will omit the label.
      #
      # If a block is given, it will be yielded with the label content, and after the label and
      # error message.
      def label(**kwargs, &block)
        content = attributes.delete(:label)

        super(**kwargs) do
          captured = capture do
            div do
              span { content || translate_label } if content != false
              error? && span(part: :error) { error_message }
            end
          end

          if !block
            yield_content_with_no_args { captured }
          elsif block.arity == 1
            yield captured
          else
            yield_content_with_no_args { captured }
            yield
          end
        end
      end

      def hint(content = nil)
        content ||= attributes.delete(:hint)

        return if content == false

        content ||= translate(:hints)
        content.present? && div(part: :hint) { unsafe_raw content }
      end

      def field_type
        @field_type ||= self.class.name.demodulize.underscore
      end

      def field_name(*names, multiple: false)
        names.prepend attribute.last

        if nested?
          if nested_attributes_association?
            names.prepend "#{attribute.first}_attributes"
          else
            names.prepend attribute.first
          end
        elsif names.count == 1 && names.first.is_a?(String)
          return names.first
        end

        form.field_name(*names, multiple:)
      end

      def field_id(*args)
        form.field_id(*attribute, *args)
      end

      def translate(namespace, postfix: nil, default: '')
        form.translate namespace, attribute, postfix:, default:
      end

      def translate_label(default: nil)
        form.translate_label attribute, default:
      end

      def build_attributes(**attrs)
        attributes.merge(attrs).tap do |x|
          x[:class] ||= form.css_module(:input)
          x[:value] ||= value.to_s
        end
      end

      def value
        attr = attribute.last
        if actual_model.respond_to?(attr)
          actual_model.public_send(attribute.last)
        else
          ''
        end
      end

      # @return [Boolean] true if the attribute is nested, otherwise false.
      def nested?
        attribute.count > 1
      end

      def nested_attributes_association?
        parent_model.respond_to?(:"#{attribute.first}_attributes=")
      end

      # @return the nested model if nested, otherwise nil.
      def nested_model
        @nested_model ||= nested? ? model.public_send(attribute.first) : nil
      end

      def actual_model
        @actual_model ||= nested_model || model
      end

      alias parent_model model

      def virtual_path
        @virtual_path ||= Proscenium::Resolver.resolve self.class.source_path.sub_ext('.jsx').to_s
      end
    end
  end
end
