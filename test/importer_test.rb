# frozen_string_literal: true

require 'test_helper'

class Proscenium::ImporterTest < ActiveSupport::TestCase
  setup do
    Proscenium::Importer.reset
  end

  test '.import single file' do
    Proscenium::Importer.import '/app/views/layouts/application.js'

    assert_equal({ '/app/views/layouts/application.js' => {} }, Proscenium::Importer.imported)
  end

  test '.import with options' do
    Proscenium::Importer.import '/app/views/layouts/application.js', name: 'bob'

    assert_equal({
                   '/app/views/layouts/application.js' => { name: 'bob' }
                 }, Proscenium::Importer.imported)
  end

  test '.import multiple calls' do
    Proscenium::Importer.import '/app/views/layouts/application.js'
    Proscenium::Importer.import '/app/views/layouts/application.css'

    assert_equal({
                   '/app/views/layouts/application.js' => {},
                   '/app/views/layouts/application.css' => {}
                 }, Proscenium::Importer.imported)
  end

  test '.import duplicate paths' do
    Proscenium::Importer.import '/app/views/layouts/application.js'
    Proscenium::Importer.import '/app/views/layouts/application.js'

    assert_equal({ '/app/views/layouts/application.js' => {} }, Proscenium::Importer.imported)
  end

  # test '#imported?' do
  #   refute Proscenium::Importer.imported?('/app/views/layouts/application.js')

  #   Proscenium::Importer.import '/app/views/layouts/application.js'

  #   assert Proscenium::Importer.imported?('/app/views/layouts/application.js')
  # end

  test '.sideload' do
    mock_files 'app/views/user.rb', 'app/views/user.js', 'app/views/user.css' do
      Proscenium::Importer.sideload Rails.root.join('app/views/user.rb')
    end

    assert_equal({
                   '/app/views/user.js' => { sideloaded: true },
                   '/app/views/user.css' => { sideloaded: true }
                 }, Proscenium::Importer.imported)
  end

  test '.sideload; no js, no css' do
    mock_file 'app/views/user.rb' do
      Proscenium::Importer.sideload Rails.root.join('app/views/user.rb')
    end

    assert_nil Proscenium::Importer.imported
  end

  test '.sideload; no js' do
    mock_files 'app/views/user.rb', 'app/views/user.css' do
      Proscenium::Importer.sideload Rails.root.join('app/views/user.rb')
    end

    assert_equal({ '/app/views/user.css' => { sideloaded: true } }, Proscenium::Importer.imported)
  end

  test '.sideload; .module.css before .css' do
    mock_files 'app/views/user.rb', 'app/views/user.css', 'app/views/user.module.css' do
      Proscenium::Importer.sideload Rails.root.join('app/views/user.rb')
    end

    assert_equal({ '/app/views/user.module.css' => { sideloaded: true } }, Proscenium::Importer.imported)
  end

  def mock_file(*paths)
    FakeFS.with_fresh do
      paths.each do |path|
        path = Rails.root.join(path)
        path.dirname.mkpath
        FileUtils.touch(path.to_s, noop: true)
      end

      yield
    end
  end
  alias mock_files mock_file
end
