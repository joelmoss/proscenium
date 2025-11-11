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

    test 'bare specifier (NPM package)' do
      assert_equal '/node_modules/pkg/index.js', subject.resolve('pkg')
    end

    test 'absolute file system path' do
      assert_equal '/lib/foo.js', subject.resolve(Rails.root.join('lib/foo.js').to_s)
    end

    test 'absolute URL path' do
      assert_equal '/lib/foo.js', subject.resolve('/lib/foo.js')
    end

    test 'proscenium runtime' do
      assert_equal '/node_modules/@rubygems/proscenium/react-manager/index.jsx',
                   subject.resolve('@rubygems/proscenium/react-manager/index.jsx')
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
          subject.resolve('@rubygems/proscenium/react-manager/index.jsx', as_array: true)

        assert_nil manifest_path
        assert_equal '/node_modules/@rubygems/proscenium/react-manager/index.jsx', non_manifest_path
        assert_equal Proscenium.root.join('lib/proscenium/react-manager/index.jsx').to_s, abs_path
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
