# frozen_string_literal: true

require 'test_helper'

class Proscenium::ResolverTest < ActiveSupport::TestCase
  let(:subject) { Proscenium::Resolver }

  describe '.resolve' do
    it 'raises on non-absolute path' do
      error = assert_raises ArgumentError do
        subject.resolve('./foo')
      end
      assert_equal '`path` must be an absolute file system or URL path', error.message
    end

    it 'raises on unknown path' do
      assert_raises Proscenium::Builder::ResolveError do
        subject.resolve('unknown')
      end
    end

    # The guard has to see the normalised path, or a Windows-spelled relative path walks past it.
    it 'raises on a Windows-form relative path' do
      assert_raises ArgumentError do
        as_platform(true) { subject.resolve('..\\foo.js') }
      end
    end

    test 'bare specifier (NPM package)' do
      assert_equal '/node_modules/pkg/index.js', subject.resolve('pkg')
    end

    test 'absolute file system path' do
      assert_equal '/lib/foo.js', subject.resolve(Rails.root.join('lib/foo.js').to_s)
    end

    it 'resolves a URL, which has no file' do
      assert_equal 'https://cdn.example/x.js', subject.resolve('https://cdn.example/x.js')
    end

    # The bun test harness passes Bun's own spelling of a module path, which on Windows uses
    # backslashes. Left as it was, it missed the Rails.root match and came back unresolved.
    it 'resolves a Windows-form file system path as its slash form' do
      windows_path = "#{Rails.root.to_s.tr('/', '\\')}\\lib\\foo.js"
      manifest_path, url_path, abs_path =
        as_platform(true) { subject.resolve(windows_path, as_array: true) }

      assert_nil manifest_path
      assert_equal '/lib/foo.js', url_path
      assert_equal Rails.root.join('lib/foo.js').to_s, abs_path
    end

    test 'absolute URL path' do
      assert_equal '/lib/foo.js', subject.resolve('/lib/foo.js')
    end

    it 'resolves an absolute file system path inside a gem' do
      path = Proscenium.root.join('lib/proscenium/runtime/bun.js').to_s
      assert_equal '/node_modules/@rubygems/proscenium/runtime/bun.js',
                   subject.resolve(path)
    end

    test 'proscenium runtime' do
      assert_equal '/node_modules/@rubygems/proscenium/runtime/bun.js',
                   subject.resolve('@rubygems/proscenium/runtime/bun.js')
    end

    # #95: the gem path was interpolated into a regex, so `+` left this path unmapped and an
    # unbalanced `(` raised RegexpError.
    it 'resolves a path inside a gem whose path holds regex metacharacters' do
      original = Proscenium::BundledGems.method(:paths)
      Proscenium::BundledGems.define_singleton_method(:paths) do
        { 'gem1' => '/gems/gem1-1.0+build', 'gem2' => '/gems/(gem2' }
      end

      assert_equal '/node_modules/@rubygems/gem1/x.js', subject.resolve('/gems/gem1-1.0+build/x.js')
      assert_equal '/node_modules/@rubygems/gem2/x.js', subject.resolve('/gems/(gem2/x.js')
    ensure
      Proscenium::BundledGems.define_singleton_method(:paths, original)
    end

    it 'resolves css module from file:* npm install' do
      assert_equal '/node_modules/pkg/one.module.css', subject.resolve('pkg/one.module.css')
    end

    it 'resolves css module from @rubygems/* and file:* npm install' do
      assert_equal(
        '/node_modules/@rubygems/gem_file/index.module.css',
        subject.resolve('@rubygems/gem_file/index.module.css')
      )
    end

    describe 'as_array: true' do
      it 'raises on non-absolute path' do
        error = assert_raises ArgumentError do
          subject.resolve('./foo', as_array: true)
        end
        assert_equal '`path` must be an absolute file system or URL path', error.message
      end

      it 'raises on unknown path' do
        assert_raises Proscenium::Builder::ResolveError do
          subject.resolve('unknown', as_array: true)
        end
      end

      # Go answers a URL with an empty file path, and this is the wrapper importer.rb and the
      # runtime server actually call.
      it 'resolves a URL, which has no file' do
        manifest_path, non_manifest_path, abs_path =
          subject.resolve('https://cdn.example/x.js', as_array: true)

        assert_nil manifest_path
        assert_equal 'https://cdn.example/x.js', non_manifest_path
        assert_equal '', abs_path
      end

      test 'bare specifier (NPM package)' do
        manifest_path, non_manifest_path, abs_path = subject.resolve('pkg', as_array: true)

        assert_nil manifest_path
        assert_equal '/node_modules/pkg/index.js', non_manifest_path
        assert_equal Rails.root.join('node_modules/pkg/index.js').to_s, abs_path
      end

      test 'absolute file system path' do
        manifest_path, non_manifest_path, abs_path = subject.resolve('lib/foo.js', as_array: true)

        assert_nil manifest_path
        assert_equal '/lib/foo.js', non_manifest_path
        assert_equal Rails.root.join('lib/foo.js').to_s, abs_path
      end

      test 'absolute URL path' do
        manifest_path, non_manifest_path, abs_path = subject.resolve('/lib/foo.js', as_array: true)

        assert_nil manifest_path
        assert_equal '/lib/foo.js', non_manifest_path
        assert_equal Rails.root.join('lib/foo.js').to_s, abs_path
      end

      test 'proscenium runtime' do
        manifest_path, non_manifest_path, abs_path =
          subject.resolve('@rubygems/proscenium/runtime/bun.js', as_array: true)

        assert_nil manifest_path
        assert_equal '/node_modules/@rubygems/proscenium/runtime/bun.js', non_manifest_path
        assert_equal Proscenium.root.join('lib/proscenium/runtime/bun.js').to_s, abs_path
      end

      it 'resolves css module from file:* npm install' do
        manifest_path, non_manifest_path, abs_path = subject.resolve('pkg/one.module.css',
                                                                     as_array: true)

        assert_nil manifest_path
        assert_equal '/node_modules/pkg/one.module.css', non_manifest_path
        assert_equal Rails.root.join('node_modules/pkg/one.module.css').to_s, abs_path
      end

      it 'resolves css module from @rubygems/* and file:* npm install' do
        manifest_path, non_manifest_path, abs_path =
          subject.resolve('@rubygems/gem_file/index.module.css', as_array: true)

        assert_nil manifest_path
        assert_equal '/node_modules/@rubygems/gem_file/index.module.css', non_manifest_path
        assert_equal Proscenium.root.join('fixtures/dummy/vendor/gem_file/index.module.css').to_s,
                     abs_path
      end
    end
  end
end
