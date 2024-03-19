# frozen_string_literal: true

require 'ruby-next/language'
require 'proscenium/core_ext/object/css_module_ivars'

module Proscenium
  module CssModule
    class Rewriter < RubyNext::Language::Rewriters::Text
      NAME = 'proscenium-css-module'

      def rewrite(source)
        source = source.gsub(/%i\[((@[\w@ ]+)|([\w@ ]+ @[\w@ ]+))\]/) do |_|
          arr = ::Regexp.last_match(1).split.map do |x|
            x.start_with?('@') ? css_module_string(x[1..]) : ":#{x}"
          end
          "[#{arr.join(',')}]"
        end

        source.gsub(/:@([\w]+)/) do |_|
          context.track!(self)
          css_module_string(::Regexp.last_match(1))
        end
      end

      private

      def css_module_string(name)
        if (path = Pathname.new(context.path).sub_ext('.module.css')).exist?
          tname = Transformer.new(path).class_name!(name, name.dup).first
          "Proscenium::CssModule::Name.new(:@#{name}, '#{tname}')"
        else
          "Proscenium::CssModule::Name.new(:@#{name}, css_module(:#{name}))"
        end
      end
    end
  end
end

RubyNext::Language.send :include_patterns=, []
RubyNext::Language.include_patterns << "#{Rails.root.join('app', 'components')}/*.rb"
RubyNext::Language.include_patterns << "#{Rails.root.join('app', 'views')}/*.rb"
RubyNext::Language.rewriters = [Proscenium::CssModule::Rewriter]

require 'ruby-next/language/runtime'
