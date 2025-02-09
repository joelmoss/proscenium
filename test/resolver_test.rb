# frozen_string_literal: true

require 'test_helper'

class Proscenium::ResolverTest < ActiveSupport::TestCase
  let(:subject) { Proscenium::Resolver }

  describe '.resolve' do
    context './foo' do
      it 'raises' do
        error = assert_raises ArgumentError do
          subject.resolve('./foo')
        end
        assert_equal 'path must be an absolute file system or URL path', error.message
      end
    end

    context 'unknown path' do
      it 'raises' do
        assert_raises Proscenium::Builder::ResolveError do
          subject.resolve('unknown')
        end
      end
    end

    context 'bare specifier (NPM package)' do
      it 'resolves' do
        assert_equal '/packages/mypackage/index.js', subject.resolve('mypackage')
      end
    end

    context 'absolute file system path' do
      it 'resolves' do
        assert_equal '/lib/foo.js', subject.resolve(Rails.root.join('lib/foo.js').to_s)
      end
    end

    context 'absolute URL path' do
      it 'resolves' do
        assert_equal '/lib/foo.js', subject.resolve('/lib/foo.js')
      end
    end

    context 'proscenium runtime' do
      it 'resolves' do
        assert_equal '/proscenium/react-manager/index.jsx',
                     subject.resolve('proscenium/react-manager/index.jsx')
      end
    end
  end
end
