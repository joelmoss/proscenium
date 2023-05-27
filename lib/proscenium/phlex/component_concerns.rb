# frozen_string_literal: true

module Proscenium::Phlex::ComponentConcerns
  module CssModules
    extend ActiveSupport::Concern
    include Proscenium::CssModule
    include Proscenium::Phlex::ResolveCssModules

    # class_methods do
    #   # FIXME: Still needed?
    #   def path
    #     pp name, super
    #     pp Module.const_source_location(name).first

    #     name && Pathname.new(Module.const_source_location(name).first)
    #   rescue NameError
    #     nil
    #   end
    # end

    private

    def path
      self.class.path
    end
  end
end
