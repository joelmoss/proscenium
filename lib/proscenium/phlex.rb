# frozen_string_literal: true

module Proscenium
  module Phlex
    module Sideload
      def template(...)
        Proscenium::SideLoad.append asset_path if Rails.application.config.proscenium.side_load
        super
      end
    end

    module CompileCssModules
      def call(...)
        Rails.env.test? ? super : cssm.compile_class_names(super)
      end
    end

    def self.included(mod)
      mod.prepend Sideload, CompileCssModules
    end

    def css_module(name)
      cssm.class_names(name).join ' '
    end

    private

    # FIXME: !!
    def asset_path
      @asset_path ||= __FILE__.delete_prefix(Rails.root.to_s).delete_suffix('.rb')[1..]
    end

    def cssm
      @cssm ||= Proscenium::CssModule.new(asset_path)
    end
  end
end
