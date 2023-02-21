# frozen_string_literal: true

require 'test_helper'

class Proscenium::Esbuild::GolibTest < Minitest::Test
  def test_transform
    result = Proscenium::Esbuild::Golib.transform('let x = 1+2')

    assert_equal "let x = 1 + 2;\n", result
  end

  focus
  def test_build
    result = Proscenium::Esbuild::Golib.build(Rails.root.join('lib/foo.js').to_s)

    assert_equal "console.log(\"/lib/foo.js\");\n", result
  end
end
