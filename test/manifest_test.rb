# frozen_string_literal: true

require 'test_helper'

class Proscenium::ManifestTest < ActiveSupport::TestCase
  # describe '.load' do
  #   it 'loads manifest file' do
  #     orig_manifest_path = Proscenium.config.manifest_path
  #     Proscenium.config.manifest_path = Rails.root.join('public/.manifest.json')

  #     Proscenium::Manifest.load!
  #     assert_equal({
  #                    'app/models/event.js' => '/assets/app/models/event-IANKT5DW.js',
  #                    'app/models/user.js' => '/assets/app/models/user-F53SIREM.js'
  #                  }, Proscenium::Manifest.manifest)
  #   ensure
  #     Proscenium.config.manifest_path = orig_manifest_path
  #     Proscenium::Manifest.reset!
  #   end
  # end
end
