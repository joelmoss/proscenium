# frozen_string_literal: true

require 'phlex-rails'

module Proscenium
  class Phlex < ::Phlex::HTML
    include Proscenium::SourcePath
    include CssModules
    include AssetInclusions

    module Sideload
      def before_template
        Proscenium::SideLoad.sideload_inheritance_chain self,
                                                        helpers.controller.sideload_assets_options

        super
      end
    end

    class_attribute :sideload_assets_options

    class << self
      attr_accessor :abstract_class

      def inherited(child)
        child.prepend Sideload

        super
      end

      def sideload_assets(value)
        self.sideload_assets_options = value
      end
    end
  end
end
