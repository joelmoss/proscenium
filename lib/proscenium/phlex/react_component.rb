# frozen_string_literal: true

#
# Renders a <div> for use with React components, with data attributes specifying the component path
# and props.
#
# If a block is given, it will be yielded within the div, allowing for a custom "loading" UI. If no
# block is given, then a "loading..." text will be rendered. It is intended that the component is
# mounted to this div, and the loading UI will then be replaced with the component's rendered
# output.
#
# You can pass props to the component in the `:props` keyword argument.
#
class Proscenium::Phlex::ReactComponent < Proscenium::Phlex
  self.abstract_class = true

  include Proscenium::Componentable
  include Proscenium::Phlex::ComponentConcerns::CssModules

  # Override this to provide your own loading UI.
  #
  # @example
  #   def template(**attributes, &block)
  #     super do
  #       'Look at me! I am loading now...'
  #     end
  #   end
  #
  # @yield the given block to a `div` within the top level component div.
  def template(**attributes, &block)
    send root_tag, **{ data: data_attributes }.deep_merge(attributes), &block
  end
end
