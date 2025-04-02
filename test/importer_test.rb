# frozen_string_literal: true

require 'test_helper'

class Proscenium::ImporterTest < ActiveSupport::TestCase
  before do
    Proscenium::Importer.reset
    Proscenium::Resolver.reset
  end

  let(:subject) { Proscenium::Importer }

  describe '.import' do
    it 'single file' do
      subject.import '/app/views/layouts/application.js'

      assert_equal({ '/app/views/layouts/application.js' => {} }, subject.imported)
    end

    it 'passes additional kwargs' do
      subject.import '/app/views/layouts/application.js', name: 'bob'

      assert_equal({
                     '/app/views/layouts/application.js' => { name: 'bob' }
                   }, subject.imported)
    end

    it 'concatanates multiple calls' do
      subject.import '/app/views/layouts/application.js'
      subject.import '/app/views/layouts/application.css'

      assert_equal({
                     '/app/views/layouts/application.js' => {},
                     '/app/views/layouts/application.css' => {}
                   }, subject.imported)
    end

    it 'deduplicates paths' do
      subject.import '/app/views/layouts/application.js'
      subject.import '/app/views/layouts/application.js'

      assert_equal({ '/app/views/layouts/application.js' => {} }, subject.imported)
    end

    it 'imports @rubygems/* runtime files' do
      subject.import '@rubygems/proscenium/react-manager/index.jsx'

      assert_equal({ '/node_modules/@rubygems/proscenium/react-manager/index.jsx' => {} },
                   subject.imported)
    end
  end

  describe '.sideload' do
    context 'js and css' do
      it 'sideloads' do
        mock_files 'app/views/user.rb', 'app/views/user.js', 'app/views/user.css' do
          subject.sideload Rails.root.join('app/views/user.rb')
        end

        assert_equal({
                       '/app/views/user.js' => { sideloaded: true },
                       '/app/views/user.css' => { sideloaded: true }
                     }, subject.imported)
      end
    end

    context 'no js, no css' do
      it 'sideloads nothing' do
        mock_file 'app/views/user.rb' do
          Proscenium::Importer.sideload Rails.root.join('app/views/user.rb')
        end

        assert_nil subject.imported
      end
    end

    context 'no js' do
      it 'sideloads' do
        mock_files 'app/views/user.rb', 'app/views/user.css' do
          subject.sideload Rails.root.join('app/views/user.rb')
        end

        assert_equal({ '/app/views/user.css' => { sideloaded: true } }, subject.imported)
      end
    end

    context '.module.css and .css' do
      it 'does not sideload css module' do
        mock_files 'app/views/user.rb', 'app/views/user.css', 'app/views/user.module.css' do
          subject.sideload Rails.root.join('app/views/user.rb')
        end

        assert_not_equal({ '/app/views/user.module.css' => {
                           sideloaded: true, digest: 'ab65a4fd'
                         } }, subject.imported)
      end
    end
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
