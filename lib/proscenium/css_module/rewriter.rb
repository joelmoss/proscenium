# frozen_string_literal: true

require 'ruby-next/language/runtime'
require 'proscenium/core_ext/object/css_module_ivars'

module Proscenium
  module CssModule
    class Rewriter < RubyNext::Language::Rewriters::Text
      NAME = 'proscenium-css-module'

      def safe_rewrite(source)
        source.gsub(/:@([\w_]+)/) do |_|
          context.track! self

          match = ::Regexp.last_match(1)
          "Proscenium::CssModule::Name.new(:@#{match}, css_module(:#{match}))"
        end
      end
    end
  end
end

RubyNext::Language.rewriters << Proscenium::CssModule::Rewriter
