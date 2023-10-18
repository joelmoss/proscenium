# frozen_string_literal: true

module Proscenium::UI
  class Breadcrumbs::Component < Component
    include Phlex::Rails::Helpers::URLFor

    # The path (route) to use as the HREF for the home segment. Defaults to `:root`.
    option :home_path, Types::String | Types::Symbol, default: -> { :root }

    # Assign false to hide the home segment.
    option :with_home, Types::Bool, default: -> { true }

    # HTML class name for the wrapping div element. Assigning this will override the default.
    # Defaults to `:@base`.
    option :class_name, Types::String | Types::Symbol | Types::Nominal::Nil, default: -> { :@base }

    def template
      div class: class_name do
        ol do
          if with_home
            li do
              home_template
            end
          end

          breadcrumbs.each do |ce|
            li do
              path = ce.path
              path.nil? ? ce.name : a(href: url_for(path)) { ce.name }
            end
          end
        end
      end
    end

    private

    # Override this to customise the home breadcrumb. You can call super with a block to use the
    # default template, but with custom content.
    #
    # @example
    #  def home_template
    #    super { 'hello' }
    #  end
    def home_template(&block)
      a(href: url_for(home_path)) { block&.call() || 'Home' }
    end

    # Don't render if @hide_breadcrumbs is true.
    def render?
      helpers.assigns['hide_breadcrumbs'] != true
    end

    def breadcrumbs
      helpers.controller.breadcrumbs.map { |e| Breadcrumbs::ComputedElement.new e, helpers }
    end
  end
end
