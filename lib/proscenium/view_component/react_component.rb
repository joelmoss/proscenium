# frozen_string_literal: true

#
# Renders HTML markup suitable for use with @proscenium/component-manager.
#
# If a content block is given, that content will be rendered inside the component, allowing for a
# "loading" UI. If no block is given, then a loading text will be rendered.
#
# The parent div is not decorated with any attributes, apart from the selector class required by
# component-manager. But if your component has a side loaded CSS module stylesheet
# (component.module.css), with a `.component` class defined, then that class will be assigned to the
# parent div as a CSS module.
#
class Proscenium::ViewComponent::ReactComponent < Proscenium::ViewComponent
  self.abstract_class = true

  attr_accessor :props

  # @param props: [Hash]
  # @param [Block]
  def initialize(props: {})
    @props = props

    super
  end

  def call
    tag.div class: ['componentManagedByProscenium', css_module(:component)],
            data: { component: { path: virtual_path, props: props } } do
      tag.div content || 'loading...'
    end
  end
end
