# frozen_string_literal: true

require 'phlex'

module Proscenium
  class Phlex < ::Phlex::View
    extend ActiveSupport::Autoload

    autoload :Component
    autoload :ReactComponent

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
        Proscenium::SideLoad.append self.class.path if Rails.application.config.proscenium.side_load

        super
      end
    end

    class << self
      attr_accessor :path

      def inherited(child)
        path = caller_locations(1, 1)[0].path
        child.path = path.delete_prefix(::Rails.root.to_s).delete_suffix('.rb')[1..]

        child.prepend Sideload
        child.include Helpers

        super
      end
    end

    def css_module(name)
      cssm.class_names!(name).join ' '
    end

    private

    def cssm
      @cssm ||= Proscenium::CssModule.new(self.class.path)
    end
  end
end
