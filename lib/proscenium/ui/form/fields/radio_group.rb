# frozen_string_literal: true

module Proscenium::UI::Form::Fields
  # Render a group of <radio> inputs for the given model attribute. It supports ActiveRecord
  # associations and enums.
  #
  # ## Supported options
  #
  # - options [Array] a list of options where each will render a radio input. If this is given, the
  #     automatic detection of options will be disabled. A flat array of strings will be used for
  #     both the label and value. While an Array of nested two-level arrays will be used.
  class RadioGroup < Base
    register_element :pui_radio_group

    def before_template
      @options_from_attributes = attributes.delete(:options)

      super
    end

    def view_template
      field :pui_radio_group do
        label

        div part: :radio_group_inputs do
          options.each do |opt|
            form.radio_input(*attribute, name: field_name, value: opt[:value], label: opt[:label],
                                         checked: opt[:checked], **attributes)
          end
        end

        hint
      end
    end

    private

    def field_name(*names, multiple: false)
      names.prepend association_attribute? ? association_attribute : attribute.last

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

    def options
      if @options_from_attributes
        @options_from_attributes.map do |x|
          if x.is_a?(Array)
            { value: x.first, label: x.last, checked: checked?(x.first) }
          else
            { value: x, label: x, checked: checked?(x) }
          end
        end
      elsif enum_attribute?
        fetch_enum_collection.map do |x|
          {
            value: x,
            label: model_class.human_attribute_name("#{attribute.last}.#{x}"),
            checked: checked?(x)
          }
        end
      elsif association_attribute?
        fetch_association_collection.map do |x|
          {
            value: x.id,
            label: x.to_s,
            checked: checked?(x)
          }
        end
      end
    end

    def value
      if actual_model.respond_to?(model_attribute)
        actual_model.public_send(model_attribute)
      else
        ''
      end
    end

    # Is the given `option` the current value (checked)?
    def checked?(option)
      if !option.is_a?(String) && !option.is_a?(Integer) && association_attribute?
        reflection = association_reflection
        key = if reflection.respond_to?(:options) && reflection.options[:primary_key]
                reflection.options[:primary_key]
              else
                option.class.primary_key.to_s
              end
        option.attributes[key] == value
      else
        option.to_s == value.to_s
      end
    end

    def model_attribute
      @model_attribute ||= association_attribute? ? association_attribute : attribute.last
    end

    def enum_attribute?
      model_class.defined_enums.key?(attribute.last.to_s)
    end

    def association_attribute?
      association_reflection.present?
    end

    def association_attribute
      @association_attribute ||= begin
        reflection = association_reflection

        case reflection.macro
        when :belongs_to
          (reflection.respond_to?(:options) && reflection.options[:foreign_key]&.to_sym) ||
            :"#{reflection.name}_id"
        else
          # Force the association to be preloaded for performance.
          if actual_model.respond_to?(attribute.last)
            target = actual_model.send(attribute.last)
            target.to_a if target.respond_to?(:to_a)
          end

          :"#{reflection.name.to_s.singularize}_ids"
        end
      end
    end

    def association_reflection
      @association_reflection ||= model_class.try :reflect_on_association, attribute.last
    end

    def fetch_association_collection
      relation = association_reflection.klass.all

      # association_reflection.macro == :has_many

      if association_reflection.respond_to?(:scope) && association_reflection.scope
        relation = if association_reflection.scope.parameters.any?
                     association_reflection.klass.instance_exec(actual_model,
                                                                &association_reflection.scope)
                   else
                     association_reflection.klass.instance_exec(&association_reflection.scope)
                   end
      else
        order = association_reflection.options[:order]
        conditions = association_reflection.options[:conditions]
        conditions = actual_model.instance_exec(&conditions) if conditions.respond_to?(:call)

        relation = relation.where(conditions) if relation.respond_to?(:where) && conditions.present?
        relation = relation.order(order) if relation.respond_to?(:order)
      end

      relation
    end

    def fetch_enum_collection
      actual_model.defined_enums[attribute.last.to_s].keys
    end

    def model_class
      @model_class ||= actual_model.class
    end
  end
end
