# frozen_string_literal: true

require 'phlex-rails'

module Proscenium
  class Phlex < ::Phlex::HTML
    extend ActiveSupport::Autoload
    include Proscenium::CssModule

    autoload :Page
    autoload :ReactComponent
    autoload :ResolveCssModules

    module Helpers
      def side_load_javascripts(...)
        return unless (output = @_view_context.side_load_javascripts(...))

        @_target << output
      end

      %i[side_load_stylesheets proscenium_dev].each do |name|
        define_method name do
          if (output = @_view_context.send(name))
            @_target << output
          end
        end
      end
    end

    # Side loads the class, and its super classes that respond to `.path`. Assign the
    # `abstract_class` class variable to any abstract class, and it will not be side loaded.
    # Additionally, if the class responds to `side_load`, then that method is called.
    module Sideload
      def before_template
        klass = self.class

        if !klass.abstract_class && respond_to?(:side_load, true)
          side_load
          klass = klass.superclass
        end

        while !klass.abstract_class && klass.respond_to?(:path) && klass.path
          Proscenium::SideLoad.append klass.path
          klass = klass.superclass
        end

        super
      end
    end

    class << self
      attr_accessor :path, :abstract_class

      def inherited(child)
        child.path = if caller_locations(1, 1).first.label == 'inherited'
                       Pathname.new caller_locations(2, 1).first.path
                     else
                       Pathname.new caller_locations(1, 1).first.path
                     end

        child.prepend Sideload if Rails.application.config.proscenium.side_load
        child.include Helpers

        super
      end
    end
  end
end
