# frozen_string_literal: true

require 'test_helper'

class CompilerTest < Minitest::Test
  focus
  def test_that_it_has_a_version_number
    pp Proscenium::Compiler.build
  end
end
