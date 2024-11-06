# frozen_string_literal: true

class Proscenium::UI::Form
  module FieldMethods
    # Renders a hidden input field.
    #
    # @param args [Array<Symbol>] name or nested names of model attribute
    # @param attributes [Hash] passed through to each input
    def hidden_field(*args, **)
      render Fields::Hidden.new(args, @model, self, **)
    end

    # @param args [Array<Symbol>] name or nested names of model attribute
    # @param attributes [Hash] passed through to each input
    def rich_textarea_field(*args, **attributes)
      merge_bang_attributes! args, attributes
      render Fields::RichTextarea.new(args, @model, self, **attributes)
    end

    # @param args [Array<Symbol>] name or nested names of model attribute
    # @param attributes [Hash] passed through to each input
    def datetime_local_field(*args, **attributes)
      merge_bang_attributes! args, attributes
      render Fields::Datetime.new(args, @model, self, **attributes)
    end

    # @param args [Array<Symbol>] name or nested names of model attribute
    # @param attributes [Hash] passed through to each input
    def checkbox_field(*args, **attributes)
      merge_bang_attributes! args, attributes
      render Fields::Checkbox.new(args, @model, self, **attributes)
    end

    # @param args [Array<Symbol>] name or nested names of model attribute
    # @param attributes [Hash] passed through to each input
    def tel_field(*args, **attributes)
      merge_bang_attributes! args, attributes
      render Fields::Tel.new(args, @model, self, **attributes)
    end

    # @param args [Array<Symbol>] name or nested names of model attribute
    # @param attributes [Hash] passed through to each input
    def select_field(*args, **attributes, &)
      merge_bang_attributes! args, attributes, additional_bang_attrs: [:typeahead]
      render Fields::Select.new(args, @model, self, **attributes, &)
    end

    # @see #select_field
    def select_country_field(*args, **attributes)
      merge_bang_attributes! args, attributes
      attributes[:typeahead] = true
      attributes[:options] = '/countries'
      attributes[:component_props] = {
        items_on_search: true,
        input_props: { required: attributes.delete(:required) }
      }

      select_field(*args, **attributes)
    end

    # Renders a <textarea> field for the given `attribute`.
    #
    # @param args [Array<Symbol>] name or nested names of model attribute
    # @param attributes [Hash] passed through to each input
    def textarea_field(*args, **attributes)
      merge_bang_attributes! args, attributes
      render Fields::Textarea.new(args, @model, self, **attributes)
    end

    # Renders a group of radio inputs for each option of the given `field`.
    #
    # @param args [Array<Symbol>] name or nested names of model attribute
    # @param attributes [Hash] passed through to each input
    def radio_group(*args, **attributes)
      attributes[:options] = args.pop if args.last.is_a?(Array)

      render Fields::RadioGroup.new(args, @model, self, **attributes)
    end

    def radio_field(...)
      div { radio_input(...) }
    end

    def radio_input(*args, **)
      render Fields::RadioInput.new(args, @model, self, **)
    end
  end
end
