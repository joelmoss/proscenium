# frozen_string_literal: true

require 'phlex-rails'

module Proscenium
  class Phlex < ::Phlex::HTML
    extend ActiveSupport::Autoload

    autoload :CssModules
    autoload :ReactComponent
    autoload :AssetInclusions

    include Proscenium::SourcePath
    include CssModules

    module Sideload
      def before_template
        Proscenium::SideLoad.sideload_inheritance_chain self

        super
      end
    end

    class << self
      attr_accessor :abstract_class

      def inherited(child)
        child.prepend Sideload

        super
      end
    end
  end
end
