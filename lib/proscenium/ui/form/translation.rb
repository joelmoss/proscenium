# frozen_string_literal: true

module Proscenium::UI::Form::Translation
  # Lookup translations for the given namespace using I18n, based on model name, and attribute name.
  #
  # Lookup priority with nested attributes:
  #
  #   form.{namespace}.{model}/{attribute.first}.{attribute.last}
  #   form.{namespace}.{attribute.first}.{attribute.last}
  #   form.{namespace}.{model}.{attribute.last}
  #   form.{namespace}.defaults.{attribute.last}
  #   {default}
  #
  # Lookup priority without nested attributes:
  #
  #   form.{namespace}.{model}.{attribute}
  #   form.{namespace}.defaults.{attribute}
  #   {default}
  #
  # Namespace is used for :labels and :hints.
  #
  # Model is the actual object name, for a @user object you'll have :user.
  # Attribute is the attribute itself, :name for example, or [:user, :name] if nested.
  #
  # If :postfix is given, it will be appended to the end of each lookup entry. So with a :postfix of
  # 'stuff', '_stuff' will be appended:
  #
  #   form.{namespace}.{model}.{attribute}_{postfix}
  #
  def translate(namespace, attribute, postfix: nil, default: '')
    lookups = []
    postfix = "_#{postfix}" if postfix
    model_key = model.model_name.i18n_key

    if attribute.is_a?(Array) && attribute.length > 1
      joined_attrs = attribute.join('.')
      lookups << :"#{model_key}/#{joined_attrs}#{postfix}"
      lookups << :"#{joined_attrs}#{postfix}"
      lookups << :"defaults.#{attribute.last}#{postfix}"
    else
      attribute = attribute.first if attribute.is_a?(Array)
      lookups << :"#{model_key}.#{attribute}#{postfix}"
      lookups << :"defaults.#{attribute}#{postfix}"
    end

    lookups << default

    I18n.t(lookups.shift, scope: :"#{i18n_scope}.#{namespace}",
                          default: lookups).presence
  end

  def translate_label(attribute, default: nil, postfix: nil)
    unless default
      model = @model.class

      if @model.class.respond_to?(:reflect_on_association) && attribute.count > 1
        model = @model.class.reflect_on_association(attribute.first).klass
      end

      default = model.human_attribute_name(attribute.last)
    end

    translate :labels, attribute, default:, postfix:
  end

  private

  def i18n_scope
    'form'
  end
end
