# frozen_string_literal: true

module Proscenium::UI
  # Helpers to aid in building forms and associated inputs with built-in styling, and inspired by
  # Rails form helpers.
  #
  # Start by creating the form with `Proscenium::UI::Form`, which expects a model
  # instance, and a block in which you define one or more fields. It automatically includes a hidden
  # authenticity token field for you.
  #
  # Example:
  #
  #   render Proscenium::UI::Form.new(User.new) do |f|
  #     f.text_field :name
  #     f.radio_group :role, %i[admin manager]
  #     f.submit 'Save'
  #   end
  #
  # The following fields (inputs) are available:
  #
  #   - `url_field` - <input> with 'url' type.
  #   - `text_field` - <input> with 'text' type.
  #   - `textarea_field` - <textarea>.
  #   - `rich_textarea_field` - A rich <textarea> using ActionText and Trix.
  #   - `email_field` - <input> with 'email' type.
  #   - `number_field` - <input> with 'number' type.
  #   - `color_field` - <input> with 'color' type.
  #   - `hidden_field` - <input> with 'hidden' type.
  #   - `search_field` - <input> with 'search' type.
  #   - `password_field` - <input> with 'password' type.
  #   - `tel_field` - <input> with 'tel' type.
  #   - `range_field` - <input> with 'range' type.
  #   - `time_field` - <input> with 'time' type.
  #   - `date_field` - <input> with 'date' type.
  #   - `week_field` - <input> with 'week' type.
  #   - `month_field` - <input> with 'month' type.
  #   - `datetime_local_field` - <input> with 'datetime-local' type.
  #   - `checkbox_field` - <input> with 'checkbox' type.
  #   - `radio_field` - <input> with 'radio' type.
  #   - `radio_group` - group of <input>'s with 'radio' type.
  #   - `select_field` - <select> input.
  #
  class Form < Proscenium::UI::Component
    extend ActiveSupport::Autoload

    autoload :FieldMethods
    autoload :Translation

    module Fields
      extend ActiveSupport::Autoload

      autoload :Base
      autoload :Input
      autoload :Hidden
      autoload :RadioInput
      autoload :Checkbox
      autoload :Textarea
      autoload :RichTextarea
      autoload :RadioGroup
      autoload :Select
      autoload :Tel
    end

    include FieldMethods
    include Translation

    STANDARD_METHOD_VERBS = %w[get post].freeze

    def self.input_field(method_name, type:)
      define_method method_name do |*args, **attributes|
        merge_bang_attributes! args, attributes
        render Fields::Input.new(args, @model, self, type:, **attributes)
      end
    end

    attr_reader :model

    # Initialize a form for the given `model` instance.
    #
    # @param model [Any] Model instance or record.
    # @param method [get,post,puts,patch,delete] Form method.
    # @param action [String,Array] the form action, which can be any value that can be passed to
    #   Rails `url_for` helper.
    def initialize(model, method: nil, action: nil, **attributes) # rubocop:disable Lint/MissingSuper
      # method => ^(Nilable(Union(:get, :post, :put, :patch, :delete)))

      @model = model
      @method = method
      @action = action
      @method ||= 'patch' if @model.respond_to?(:persisted?) && @model.persisted?
      @method = @method&.to_s&.downcase || 'post'
      @attributes = attributes
    end

    # Use the given `field_class` to render a custom field. This allows you to create a custom
    # form field on an as-needed basis. The `field_class` must be a subclass of
    # `Proscenium::UI::Form::Fields::Base`.
    #
    # Example:
    #
    #   render Proscenium::UI::Form.new @resource do |f|
    #     f.use_field Administrator::EmailField, :email, :required!
    #   end
    #
    # @param field_class [Class<Proscenium::UI::Form::Fields::Base>]
    # @param args [Array<Symbol>] name or nested names of model attribute
    # @param attributes [Hash] passed through to each input
    def use_field(field_class, *args, **attributes)
      merge_bang_attributes! args, attributes
      render field_class.new(args, model, self, **attributes)
    end

    # Returns a button with type of 'submit', using the `value` given.
    #
    # @param value [String] Value of the `value` attribute.
    def submit(value = 'Save', **kwargs)
      input name: 'commit', type: :submit, value:, **kwargs
    end

    # Returns a <div> with the given `message` as its content. If `message` is not given, and
    # `attribute` is, then first error message for the given model `attribute`.
    #
    # @param message [String] error message to display.
    # @param attribute [Symbol] name of the model attribute.
    def error(message: nil, attribute: nil, &content)
      if message.nil? && attribute.nil? && !content
        raise ArgumentError, 'One of `message:`, `attribute:` or a block is required'
      end

      if content
        div class: :@error, &content
      else
        div class: :@error do
          message || @model.errors[attribute]&.first
        end
      end
    end

    def view_template(&block)
      form action:, method:, **@attributes do
        method_field
        authenticity_token_field
        error_for_base
        yield_content(&block)
      end
    end

    def error_for_base
      return unless @model.errors.key?(:base)

      callout :danger do |x|
        x.title { 'Unable to save...' }
        div { @model.errors.full_messages_for(:base).first }
      end
    end

    def field_name(*names, multiple: false)
      # Delete the `?` suffix if present.
      lname = names.pop.to_s
      names.append lname.delete_suffix('?').to_sym

      @_view_context.field_name(ActiveModel::Naming.param_key(@model.class), *names,
                                multiple:)
    end

    def field_id(*args)
      @_view_context.field_id(ActiveModel::Naming.param_key(@model.class), *args)
    end

    def authenticity_token_field
      return if method == 'get'

      input(
        name: 'authenticity_token',
        type: 'hidden',
        value: @_view_context.form_authenticity_token(form_options: { action:,
                                                                      method: @method })
      )
    end

    def action
      @_view_context.url_for(@action || @model)
    end

    def method_field
      return if STANDARD_METHOD_VERBS.include?(@method)

      input type: 'hidden', name: '_method', value: @method, autocomplete: 'off'
    end

    def method
      STANDARD_METHOD_VERBS.include?(@method) ? @method : 'post'
    end

    input_field :file_field, type: 'file'
    input_field :url_field, type: 'url'
    input_field :text_field, type: 'text'
    input_field :time_field, type: 'time'
    input_field :date_field, type: 'date'
    input_field :number_field, type: 'number'
    input_field :week_field, type: 'week'
    input_field :month_field, type: 'month'
    input_field :email_field, type: 'email'
    input_field :color_field, type: 'color'
    input_field :search_field, type: 'search'
    input_field :password_field, type: 'password'
    input_field :range_field, type: 'range'

    private

    def merge_bang_attributes!(attrs, kw_attributes, additional_bang_attrs: [])
      Proscenium::Utils.merge_bang_attributes! attrs, kw_attributes,
                                               %i[required disabled].concat(additional_bang_attrs)
    end
  end
end
