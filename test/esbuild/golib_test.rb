# frozen_string_literal: true

require 'test_helper'

class Proscenium::Esbuild::GolibTest < Minitest::Test
  def test_basic_build
    result = Proscenium::Esbuild::Golib.new.build('lib/foo.js')

    assert_includes result, 'console.log("/lib/foo.js");'
  end

  def test_resolve
    result = Proscenium::Esbuild::Golib.new.resolve('/lib/foo.js')

    assert_equal '/lib/foo.js', result
  end

  def test_unknown_path
    error = assert_raises Proscenium::Esbuild::Golib::CompileError do
      Proscenium::Esbuild::Golib.new.build('unknown.js')
    end

    assert_equal "Failed to build 'unknown.js' -- Could not resolve \"unknown.js\"", error.message
  end
end
