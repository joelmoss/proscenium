# frozen_string_literal: true

require 'test_helper'

class ResolvePathTest < ActiveSupport::TestCase
  setup do
    Proscenium.config.side_load_gems = {}
    Proscenium::Importer.reset
  end

  test 'raise when path is not a string' do
    assert_raises ArgumentError do
      Proscenium::Utils.resolve_path(123)
    end
  end

  test 'raise when path is relative' do
    assert_raises ArgumentError do
      Proscenium::Utils.resolve_path('./foo')
    end
  end

  test 'unknown path' do
    assert_raises Proscenium::Builder::ResolveError do
      Proscenium::Utils.resolve_path('unknown')
    end
  end

  test 'bare specifier (NPM package)' do
    assert_equal '/packages/mypackage/index.js', Proscenium::Utils.resolve_path('mypackage')
  end

  test 'absolute file system path' do
    assert_equal '/lib/foo.js', Proscenium::Utils.resolve_path(Rails.root.join('lib/foo.js').to_s)
  end

  test 'absolute URL path' do
    assert_equal '/lib/foo.js', Proscenium::Utils.resolve_path('/lib/foo.js')
  end

  test 'side loaded gem' do
    Proscenium.config.side_load_gems['mygem'] = {
      root: '/my/gem/root',
      package_name: 'gem1'
    }

    assert_equal '/vendor/gem1/lib/gem1/gem1.js',
                 Proscenium::Utils.resolve_path('/my/gem/root/lib/gem1/gem1.js')
  end
end
