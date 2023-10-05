# frozen_string_literal: true

require 'phlex-rails'

module Proscenium
  class Phlex < ::Phlex::HTML
    extend ActiveSupport::Autoload

    autoload :CssModules
    autoload :ReactComponent

    extend ::Phlex::Rails::HelperMacros
    include ::Phlex::Rails::Helpers::JavaScriptIncludeTag
    include ::Phlex::Rails::Helpers::StyleSheetLinkTag
    include Proscenium::SourcePath
    include CssModules

    define_output_helper :side_load_stylesheets # deprecated
    define_output_helper :include_stylesheets
    define_output_helper :side_load_javascripts # deprecated
    define_output_helper :include_javascripts
    define_output_helper :declare_lazy_scripts

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
