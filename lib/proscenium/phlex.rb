# frozen_string_literal: true

module Proscenium
  class Phlex < ::Phlex::View
    module Sideload
      def template(...)
        if Rails.application.config.proscenium.side_load
          Proscenium::SideLoad.append self.class.virtual_path
        end

        super
      end
    end

    module CompileCssModules
      def call(...)
        Rails.env.test? ? super : cssm.compile_class_names(super)
      end
    end

    class << self
      attr_accessor :virtual_path

      def inherited(child)
        path = caller_locations(1, 1)[0].path
        child.virtual_path = path.delete_prefix(::Rails.root.to_s).delete_suffix('.rb')[1..]

        child.prepend Sideload, CompileCssModules

        super
      end
    end

    def css_module(name)
      cssm.class_names!(name).join ' '
    end

    private

    def cssm
      @cssm ||= Proscenium::CssModule.new(self.class.virtual_path)
    end
  end
end
