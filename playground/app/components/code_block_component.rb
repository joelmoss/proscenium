# frozen_string_literal: true

require 'phlex/testing/view_helper'

class CodeBlockComponent < ApplicationComponent
  FORMATTER = Rouge::Formatters::HTML.new

  include Dry::Initializer.define lambda {
    param :syntax, Dry::Types['coercible.symbol']
  }

  def view_template(&)
    @code = capture(&)
    @code = HtmlBeautifier.beautify(@code) if @syntax == :html

    div class: :@base do
      legend { @syntax }
      pre(class: :highlight, data:) do
        @syntax ? unsafe_raw(FORMATTER.format(lexer.lex(@code))) : @code
      end
    end
  end

  private

  def data
    { language: @syntax, lines: }
  end

  def lines
    @code.scan("\n").count + 1
  end

  def lexer
    Rouge::Lexer.find(@syntax)
  end
end
