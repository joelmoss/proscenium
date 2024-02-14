# frozen_string_literal: true

class Object
  def instance_variable_get(name)
    name.is_a?(::Proscenium::CssModule::Name) ? super(name.to_sym) : super
  end

  def instance_variable_set(name, obj)
    name.is_a?(::Proscenium::CssModule::Name) ? super(name.to_sym, obj) : super
  end

  def instance_variable_defined?(name)
    name.is_a?(::Proscenium::CssModule::Name) ? super(name.to_sym) : super
  end

  def remove_instance_variable(name)
    name.is_a?(::Proscenium::CssModule::Name) ? super(name.to_sym) : super
  end
end
