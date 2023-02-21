# frozen_string_literal: true

require 'test_helper'

class Proscenium::Esbuild::GolibTest < Minitest::Test
  def test_basic_build
    result = Proscenium::Esbuild::Golib.new.build('lib/foo.js')

    assert_includes result, 'console.log("/lib/foo.js");'
  end

  def test_unknown_path
    error = assert_raises Proscenium::Esbuild::Golib::CompileError do
      Proscenium::Esbuild::Golib.new.build('unknown.js')
    end

    assert_equal "Failed to build 'unknown.js' -- Could not resolve \"unknown.js\"", error.message
  end

  # def test_svg
  #   result = Proscenium::Esbuild::Golib.new.build('at.svg')

  #   pp result

  #   assert result[:success]
  #   assert_includes result[:response], 'console.log("/lib/foo.js");'
  # end

  focus
  def test_define_node_env
    result = Proscenium::Esbuild::Golib.new.build('lib/define_node_env.js')

    assert_includes result, 'console.log("test");'
  end
end
