# frozen_string_literal: true

module Proscenium
  # Renders a <div> for use with React components, with data attributes specifying the component
  # path and props.
  #
  # If a content block is given, that content will be rendered inside the component, allowing for a
  # "loading" UI. If no block is given, then a "loading..." text will be rendered. It is intended
  # that the component is mounted to this div, and the loading UI will then be replaced with the
  # component's rendered output.
  class ViewComponent::ReactComponent < ViewComponent
    self.abstract_class = true

    include ReactComponentable

    def call
      tag.send root_tag, data: data_attributes do
        tag.div content || 'loading...'
      end
    end
  end
end
