# frozen_string_literal: true

module Proscenium
  class Phlex < ::Phlex::View
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
