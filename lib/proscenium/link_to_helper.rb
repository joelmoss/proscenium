# frozen_string_literal: true

module Proscenium
  module LinkToHelper
    # Overrides ActionView::Helpers::UrlHelper#link_to to allow passing a component instance as the
    # URL, which will build the URL from the component path, eg. `/components/my_component`. The
    # resulting link tag will also populate the `data` attribute with the component props.
    #
    # Example:
    #   link_to 'Go to', MyComponent
    #
    # TODO: ummm, todo it! ;)
  end

  # Component handling for the `link_to` helper.
  class LinkToComponentArguments
    def initialize(options, name_argument_index, context)
      @options = options
      @name_argument_index = name_argument_index
      @component = @options[@name_argument_index]

      # We have to render the component, and then extract the props from the component. Rendering
      # first ensures that we have all the correct props.
      context.render @component
    end

    def helper_options
      @options[@name_argument_index] = "/components#{@component.virtual_path}"
      @options[@name_argument_index += 1] ||= {}
      @options[@name_argument_index][:rel] = 'nofollow'
      @options[@name_argument_index][:data] ||= {}
      @options[@name_argument_index][:data][:component] = {
        path: @component.virtual_path,
        props: @component.props
      }

      @options
    end
  end
end
