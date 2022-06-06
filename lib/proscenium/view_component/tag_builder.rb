# frozen_string_literal: true

class Proscenium::ViewComponent::TagBuilder < ActionView::Helpers::TagHelper::TagBuilder
  def tag_options(options, escape = true) # rubocop:disable Style/OptionalBooleanParameter
    super(css_module_option(options), escape)
  end

  private

  def css_module_option(options)
    return options if options.blank?

    unless (css_module = options.delete(:css_module) || options.delete('css_module'))
      return options
    end

    css_module = @view_context.css_module(css_module)

    options.tap do |x|
      x[:class] = "#{css_module} #{options.delete(:class) || options.delete('class')}".strip
    end
  end
end
