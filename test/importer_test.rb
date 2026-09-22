# frozen_string_literal: true

require 'test_helper'

class Proscenium::ImporterTest < ActiveSupport::TestCase
  before do
    Proscenium::Importer.reset
    Proscenium::Resolver.reset
  end

  let(:subject) { Proscenium::Importer }

  describe '.import' do
    test 'single file' do
      subject.import '/app/views/layouts/application.js'

      assert_equal({ '/app/views/layouts/application.js' => {} }, subject.imported)
    end

    test 'js imports css when pre-compiled' do
      Proscenium.config.precompile = Set[
        './app/components/css_module_import.js',
        './app/components/css_module_import.module.css'
      ]
      Proscenium::Builder.compile
      Proscenium::Manifest.load!

      subject.import '/app/components/css_module_import.js'

      names = subject.imported.keys
      assert_match(%r{^/assets/app/components/css_module_import-\$[A-Z0-9]{8}\$\.js$},
                   names.first)
      assert_match(%r{^/assets/app/components/css_module_import-\$[A-Z0-9]{8}\$\.css$},
                   names.last)
    ensure
      Proscenium.config.output_path.rmtree
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

    # The suffix is a pure function of the file's path, and this runs once per class name a view
    # emits, so it must not be rebuilt every time the same module is imported.
    it 'builds the css module suffix once per file, however often it is imported' do
      # The memo lasts the life of the process, so an earlier test may already have filled it for
      # this file, and then nothing would be counted.
      Proscenium::Importer::SUFFIXES.clear

      calls = 0
      original = Proscenium::Utils.method(:css_module_suffix)
      Proscenium::Utils.define_singleton_method(:css_module_suffix) do |path|
        calls += 1
        original.call(path)
      end

      digests = Array.new(5) { subject.import('/lib/css_modules/basic2.module.css') }

      assert_equal 1, digests.uniq.size
      assert_equal 1, calls
    ensure
      Proscenium::Utils.define_singleton_method(:css_module_suffix, original)
    end

    # A URL has no file on disk, so `abs_path` comes back empty. The class-name suffix used to be
    # built from a path under Rails.root that could not exist, and with no path at all it raised
    # `ArgumentError: different prefix`.
    it 'imports a remote css module, which has no file' do
      digest = subject.import('https://cdn.example/x.module.css')

      assert_match(/\A[0-9a-f]{8}_https/, digest)
      assert_equal '', subject.imported['https://cdn.example/x.module.css'][:abs_path]
    end

    # A gem on another drive than the app - RubyInstaller's gems on C:, the app on D: - has no
    # path relative to Rails.root, and relative_path_from raised, so every view using one of its
    # CSS modules failed. esbuild falls back to the absolute path for the stylesheet's class
    # names, so the suffix has to be built from that too.
    #
    # A relative path stands in for the other drive, because it is the one input
    # relative_path_from rejects on every platform: it needs both sides absolute, or both
    # relative. A real drive letter would not do, since a checkout can be on the same drive.
    it 'builds the suffix from the whole path when it has no form relative to the app' do
      Proscenium::Importer::SUFFIXES.clear
      elsewhere = 'gems/widgets/x.module.css'
      original = Proscenium::Resolver.method(:resolve)
      Proscenium::Resolver.define_singleton_method(:resolve) do |*, **|
        [nil, '/node_modules/@rubygems/widgets/x.module.css', elsewhere]
      end

      assert_equal "#{Proscenium::Utils.css_module_digest(elsewhere)}_gems-widgets-x-module",
                   subject.import('@rubygems/widgets/x.module.css')
    ensure
      Proscenium::Resolver.define_singleton_method(:resolve, original)
    end

    it 'tells two remote css modules apart' do
      refute_equal subject.import('https://cdn.example/a.module.css'),
                   subject.import('https://cdn.example/b.module.css')
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
                       '/app/views/user.js' => {},
                       '/app/views/user.css' => {}
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

        assert_equal({ '/app/views/user.css' => {} }, subject.imported)
      end
    end

    context '.module.css and .css' do
      it 'does not sideload css module' do
        mock_files 'app/views/user.rb', 'app/views/user.css', 'app/views/user.module.css' do
          subject.sideload Rails.root.join('app/views/user.rb')
        end

        assert_not_equal({ '/app/views/user.module.css' => { digest: 'ab65a4fd' } },
                         subject.imported)
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
