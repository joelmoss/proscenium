# frozen_string_literal: true

module Proscenium::Phlex::ComponentConcerns
  module CssModules
    extend ActiveSupport::Concern
    include Proscenium::CssModule
    include Proscenium::Phlex::ResolveCssModules

    class_methods do
      def path
        Pathname.new(Module.const_source_location(name).first)
      end
    end

    private

    def path
      self.class.path
    end
  end
end
