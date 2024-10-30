# frozen_string_literal: true

require 'test_helper'

class Proscenium::VersionTest < ActiveSupport::TestCase
  it 'has a version number' do
    assert_not_nil Proscenium::VERSION
  end
end
