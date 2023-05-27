# frozen_string_literal: true

require 'phlex-rails'

module Proscenium
  class Phlex < ::Phlex::HTML
    extend ActiveSupport::Autoload
    include Proscenium::CssModule

    autoload :Page
    autoload :ReactComponent
    autoload :ResolveCssModules
    autoload :ComponentConcerns

    extend ::Phlex::Rails::HelperMacros
    include ::Phlex::Rails::Helpers::JavaScriptIncludeTag
    include ::Phlex::Rails::Helpers::StyleSheetLinkTag

    define_output_helper :side_load_stylesheets
    define_output_helper :side_load_javascripts

    # Side loads the class, and its super classes that respond to `.path`. Assign the
    # `abstract_class` class variable to any abstract class, and it will not be side loaded.
    # Additionally, if the class responds to `side_load`, then that method is called.
    module Sideload
      def before_template
        klass = self.class

        if !klass.abstract_class && respond_to?(:side_load, true)
          side_load
          klass = klass.superclass
        end

        while !klass.abstract_class && klass.respond_to?(:path) && klass.path
          Proscenium::SideLoad.append klass.path
          klass = klass.superclass
        end

        super
      end
    end

    class << self
      attr_accessor :path, :abstract_class

      def inherited(child)
        unless child.path
          child.path = if caller_locations(1, 1).first.label == 'inherited'
                         Pathname.new caller_locations(2, 1).first.path
                       else
                         Pathname.new caller_locations(1, 1).first.path
                       end
        end

        child.prepend Sideload if Rails.application.config.proscenium.side_load

        super
      end
    end
  end
end
