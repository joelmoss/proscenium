# frozen_string_literal: true

require 'test_helper'

class Proscenium::VersionTest < ActiveSupport::TestCase
  it 'has a version number' do # rubocop:disable Minitest/EmptyLineBeforeAssertionMethods
    assert_not_nil Proscenium::VERSION
  end
end
