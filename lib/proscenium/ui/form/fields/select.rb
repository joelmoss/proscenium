# frozen_string_literal: true

module Proscenium::UI::Form::Fields
  #
  # Render a <select> input for the given model attribute. It will attempt to automatically build an
  # appropriate set of <option>'s, and supports ActiveRecord associations and enums. It will also
  # detect if multiple options should be enabled or not.
  #
  # ## Supported options
  #
  # - options [Array] a list of options to use for the <select>. If this is given, the automatic
  #     detection of options will be disabled. A flat array of strings will be used for both the
  #     label and value. While an Array of nested two-level arrays will be used.
  # - include_blank [Boolean, String] if true, will add an empty <option> to the <select>. If a
  #     String is given, it will be used as the label for the empty <option>.
  # - label [String] the label to use for the field (default: humanized attribute name).
  # - hint [String] the hint to use for the field (optional).
  # - required [Boolean] if true, will add the `required` attribute to the <select> tag (default:
  #     false). Also supported as a bang attribute (e.g. `:required!`). See
  #     `Hue::Utils.merge_bang_attributes!`.
  # - typeahead [Boolean] if true, will enable typeahead support by replacing with a SmartSelect
  #     React component (default: false). Also supported as a bang attribute (e.g. `:typeahead!`).
  #     See `Hue::Utils.merge_bang_attributes!`.
  #
  class Select < Base
    def self.sideload(_options)
      # Proscenium::Importer.import Hue::Phlex::ReactComponent.manager
      Proscenium::Importer.sideload source_path, lazy: true
    end

    # Ensure both the form and select field are side loaded.
    def self.css_module_path
      source_path.sub_ext('.module.css')
    end

    def before_template
      # Defined here to ensure they are deleted from `attributes` before `final_attributes` is
      # called.
      @options_from_attributes = attributes.delete(:options)
      @include_blank = attributes.delete(:include_blank)

      super
    end

    def view_template(&options_block)
      field class: :@field do
        if !options_block && typeahead?
          @component_props = attributes.delete(:component_props) || {}

          # SmartSelect - or most likely React - does not like being wrapped in a label.
          div class: :@typeahead do
            label
            div(**final_attributes)
            hint
          end
        else
          label do
            multiple? && input(name: field_name, type: :hidden, value: '')
            select(name: field_name, **final_attributes) do
              options_block ? yield_content(&options_block) : options_template
            end
            hint
          end
        end
      end
    end

    def options_template
      options.each do |value, opts|
        option(value:, selected: opts[:selected]) { opts[:label] }
      end
    end

    private

    def final_attributes
      attributes.tap do |attrs|
        if typeahead?
          attrs[:class] = :@typeahead_input
          attrs[:data] ||= {}
          attrs[:data][:proscenium_component_path] = virtual_path
          attrs[:data][:proscenium_component_props] = {
            **@component_props,
            input_name: field_name,
            multi: multiple?,
            items: options.is_a?(String) ? options : options.values,
            initial_selected_item: values_for_typeahead
          }.deep_transform_keys { |k| k.to_s.camelize :lower }.to_json
        else
          attrs[:multiple] = multiple?
        end
      end
    end

    def field_name
      names = '' if multiple?

      return super(*names) unless association_attribute?

      form.field_name association_attribute, *names
    end

    def enum_attribute?
      model_class.defined_enums.key?(attribute.last.to_s)
    end

    def association_attribute?
      association_reflection.present?
    end

    def values_for_typeahead
      if !value ||
         (value.is_a?(String) && !value.uuid?) ||
         (options.is_a?(String) && !options.uuid?)
        return value
      end

      options.filter { |k, _v| value.include?(k) }.values
    end

    def options
      @options ||= begin
        data = {}
        data[''] = empty_option if empty_option?

        if @options_from_attributes
          if @options_from_attributes.is_a?(String)
            data = @options_from_attributes
          else
            data.merge! build_options_from_attributes
          end
        elsif enum_attribute?
          fetch_enum_collection.each do |opt|
            data[opt] = {
              value: opt,
              label: model_class.human_attribute_name("#{attribute.last}.#{opt}"),
              selected: selected?(opt)
            }
          end
        elsif association_attribute?
          fetch_association_collection.each do |opt|
            data[opt.id] = {
              value: opt.id,
              label: opt.to_s,
              selected: selected?(opt)
            }
          end
        end

        data
      end
    end

    def build_options_from_attributes
      @options_from_attributes.to_h do |opt|
        label, value = option_text_and_value(opt)
        [value, { label:, value:, selected: selected?(value) }]
      end
    end

    def option_text_and_value(option)
      # Options are [text, value] pairs or strings used for both.
      if !option.is_a?(String) && option.respond_to?(:first) && option.respond_to?(:last)
        option = option.reject { |e| e.is_a?(Hash) } if option.is_a?(Array)
        [option.first, option.last]
      else
        [option, option]
      end
    end

    # Should we show the empty <option>?
    #
    # @return [Boolean]
    #   true if include_blank option is given and is true or a string.
    #   false if include_blank is given and is false.
    #   true if not required, AND attribute has no default value.
    #   true if required, AND attribute has no value.
    def empty_option
      { label: @include_blank.is_a?(String) ? @include_blank : nil }
    end

    def empty_option?
      if [true, false].include?(@include_blank)
        return @include_blank
      elsif @include_blank.is_a?(String)
        return true
      end

      return false if typeahead? || multiple?

      attributes[:required] == true ? !value? : !default_value?
    end

    def default_value?
      default_value.present?
    end

    def default_value
      model_class.new.attributes[model_attribute.to_s]
    end

    def multiple?
      association_attribute? && association_reflection.macro == :has_many
    end

    def typeahead?
      @typeahead ||= attributes.delete(:typeahead)
    end

    def value?
      value.present?
    end

    def value
      if association_attribute? && association_reflection.macro == :has_many &&
         actual_model.respond_to?(attribute.last)
        actual_model.send(model_attribute)
      else
        actual_model.attributes[model_attribute.to_s]
      end
    end

    # Is the given `option` the current value (selected)?
    def selected?(option)
      if !option.is_a?(String) && !option.is_a?(Integer) && association_attribute?
        if association_reflection.macro == :has_many && actual_model.respond_to?(attribute.last)
          actual_model.send(attribute.last).include?(option)
        else
          reflection = association_reflection
          key = if reflection.respond_to?(:options) && reflection.options[:primary_key]
                  reflection.options[:primary_key]
                else
                  option.class.primary_key.to_s
                end
          option.attributes[key] == value
        end
      else
        option == value
      end
    end

    def model_attribute
      association_attribute? ? association_attribute : attribute.last
    end

    def fetch_enum_collection
      actual_model.defined_enums[attribute.last.to_s].keys
    end

    def association_reflection
      @association_reflection ||= model_class.try :reflect_on_association, attribute.last
    end

    def fetch_association_collection
      relation = association_reflection.klass.all

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

    def association_attribute
      @association_attribute ||= begin
        reflection = association_reflection

        case reflection.macro
        when :belongs_to
          (reflection.respond_to?(:options) && reflection.options[:foreign_key]) ||
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

    def model_class
      @model_class ||= actual_model.class
    end
  end
end
