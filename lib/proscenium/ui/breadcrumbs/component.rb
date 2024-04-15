# frozen_string_literal: true

module Proscenium::UI
  class Breadcrumbs::Component < Component
    include Phlex::Rails::Helpers::URLFor

    # The path (route) to use as the HREF for the home segment. Defaults to `:root`.
    option :home_path, Types::String | Types::Symbol, default: -> { :root }

    # Assign false to hide the home segment.
    option :with_home, Types::Bool, default: -> { true }

    # One or more class name(s) for the base div element which will be appended to the default.
    option :class, Types::Coercible::String | Types::Array.of(Types::Coercible::String),
           as: :class_name, default: -> { [] }

    # One or more class name(s) for the base div element which will replace the default. If both
    # `class` and `class!` are provided, all values will be merged. Defaults to `:@base`.
    option :class!, Types::Coercible::String | Types::Array.of(Types::Coercible::String),
           as: :class_name_override, default: -> { :@base }

    def view_template
      div class: [*class_name_override, *class_name] do
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
      a(href: url_for(home_path)) do
        if block
          yield
        else
          svg role: 'img', xmlns: 'http://www.w3.org/2000/svg', viewBox: '0 0 576 512' do |s|
            s.path fill: 'currentColor',
                   d: 'M488 312.7V456c0 13.3-10.7 24-24 24H348c-6.6 0-12-5.4-12-12V356c0-6.6-5.4-' \
                      '12-12-12h-72c-6.6 0-12 5.4-12 12v112c0 6.6-5.4 12-12 12H112c-13.3 0-24-10.' \
                      '7-24-24V312.7c0-3.6 1.6-7 4.4-9.3l188-154.8c4.4-3.6 10.8-3.6 15.3 0l188 15' \
                      '4.8c2.7 2.3 4.3 5.7 4.3 9.3zm83.6-60.9L488 182.9V44.4c0-6.6-5.4-12-12-12h-' \
                      '56c-6.6 0-12 5.4-12 12V117l-89.5-73.7c-17.7-14.6-43.3-14.6-61 0L4.4 251.8c' \
                      '-5.1 4.2-5.8 11.8-1.6 16.9l25.5 31c4.2 5.1 11.8 5.8 16.9 1.6l235.2-193.7c4' \
                      '.4-3.6 10.8-3.6 15.3 0l235.2 193.7c5.1 4.2 12.7 3.5 16.9-1.6l25.5-31c4.2-5' \
                      '.2 3.4-12.7-1.7-16.9z'
          end
        end
      end
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
