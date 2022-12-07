# frozen_string_literal: true

require 'phlex'

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

    module Sideload
      def template(...)
        klass = self.class
        while klass.side_load != false && klass.respond_to?(:path) && klass.path
          Proscenium::SideLoad.append klass.path
          klass = klass.superclass
        end

        super
      end
    end

    class << self
      attr_accessor :path, :side_load

      def inherited(child)
        child.path = Pathname.new(caller_locations(1, 1)[0].path)

        child.prepend Sideload if Rails.application.config.proscenium.side_load
        child.include Helpers

        super
      end
    end
  end
end
