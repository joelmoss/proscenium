# frozen_string_literal: true

require 'test_helper'
# require 'fixtures'

class Proscenium::SourcePathTest < ActiveSupport::TestCase
  context 'phlex component' do
    it 'returns file system path to source file' do
      assert_equal Rails.root.join('app/components/phlex/plain.rb'), Phlex::Plain.source_path
    end
  end
end
