# frozen_string_literal: true

require 'test_helper'

class Proscenium::CssModule::TransformerTest < ActiveSupport::TestCase
  describe '#class_names' do
    it 'transforms class names beginning with @' do
      names = Proscenium::CssModule::Transformer.class_names('/lib/css_modules/basic', :@title)

      assert_match(/^title_[a-z0-9]{8}$/, names.first)
    end

    it 'transforms class names beginning with @ and underscore' do
      names = Proscenium::CssModule::Transformer.class_names('/lib/css_modules/basic', :@_title)

      assert_match(/^_title_[a-z0-9]{8}$/, names.first)
    end

    it 'passes through regular class names' do
      names = Proscenium::CssModule::Transformer.class_names('/lib/css_modules/basic', :title)

      assert_equal ['title'], names
    end

    it 'accepts multiple names' do
      names = Proscenium::CssModule::Transformer.class_names('/lib/css_modules/basic',
                                                             :title, :@subtitle)

      assert_equal 'title', names.first
      assert_match(/^subtitle_[a-z0-9]{8}$/, names.last)
    end

    it 'imports stylesheet' do
      Proscenium::CssModule::Transformer.class_names('/lib/css_modules/basic', :@title)

      assert_equal(['/lib/css_modules/basic.module.css'], Proscenium::Importer.imported.keys)
    end

    context 'local path' do
      it 'transforms class names' do
        names = Proscenium::CssModule::Transformer.class_names('/lib/css_modules/basic',
                                                               '/lib/css_modules/basic2@title',
                                                               :@subtitle)

        assert_match(/^title_[a-z0-9]{8}$/, names.first)
        assert_match(/^subtitle_[a-z0-9]{8}$/, names.last)
      end

      it 'imports stylesheets' do
        Proscenium::CssModule::Transformer.class_names('/lib/css_modules/basic',
                                                       '/lib/css_modules/basic2@title', :@subtitle)

        assert_equal(['/lib/css_modules/basic2.module.css', '/lib/css_modules/basic.module.css'],
                     Proscenium::Importer.imported.keys)
      end
    end

    context 'npm package path' do
      it 'transforms class names' do
        names = Proscenium::CssModule::Transformer.class_names('/lib/css_modules/basic',
                                                               'pkg/one@pkg_one_module')

        assert_match(/^pkg_one_module_[a-z0-9]{8}$/, names.first)
      end

      it 'imports stylesheets' do
        Proscenium::CssModule::Transformer.class_names('/lib/css_modules/basic',
                                                       'pkg/one@pkg_one_module')

        assert_equal(['/node_modules/pkg/one.module.css'], Proscenium::Importer.imported.keys)
      end
    end

    context 'gem path' do
      it 'transforms class names' do
        names = Proscenium::CssModule::Transformer.class_names('/lib/css_modules/basic',
                                                               '/gem2/lib/gem2/styles@foo')

        assert_match(/^foo_[a-z0-9]{8}$/, names.first)
      end

      it 'imports stylesheets' do
        Proscenium::CssModule::Transformer.class_names('/lib/css_modules/basic',
                                                       '/gem2/lib/gem2/styles@@foo')

        assert_equal(['/gem2/lib/gem2/styles.module.css'], Proscenium::Importer.imported.keys)
      end
    end
  end

  describe '.class_names' do
    context 'given path is nil' do
      let(:transformer) { Proscenium::CssModule::Transformer.new(nil) }

      it 'should raise when transforming class with leading @' do
        assert_raises Proscenium::CssModule::TransformError do
          transformer.class_names(:@title)
        end
      end

      it 'should transform regular class' do
        names = transformer.class_names(:title)

        assert_equal ['title'], names
      end

      it 'should transform local path' do
        assert_match(/^title_[a-z0-9]{8}$/,
                     transformer.class_names('/lib/css_modules/basic2@title').first)
        assert_match(/^title_[a-z0-9]{8}$/,
                     transformer.class_names('/lib/css_modules/basic2@title').first)
      end

      it 'should transform npm path' do
        names = transformer.class_names('pkg/one@pkg_one_module')

        assert_match(/^pkg_one_module_[a-z0-9]{8}$/, names.first)
      end

      it 'should transform gem path' do
        names = transformer.class_names('/gem2/lib/gem2/styles@foo')

        assert_match(/^foo_[a-z0-9]{8}$/, names.first)
      end
    end
  end

  describe '#class_names with block' do
    let(:transformer) do
      Proscenium::CssModule::Transformer.new('/lib/css_modules/basic')
    end

    it 'yields (transformed_name, side_load_path) for a `@name` reference' do
      yielded = []
      result = transformer.class_names(:@title) { |name, path| yielded << [name, path] }

      assert_equal 1, yielded.length
      assert_match(/^title_[a-z0-9]{8}_lib-css_modules-basic-module$/, yielded.first.first)
      assert_equal '/lib/css_modules/basic.module.css', yielded.first.last
      assert_equal result, [yielded.first.first]
    end

    it 'yields for a `/path@name` reference with the explicit module path' do
      yielded = []
      transformer.class_names('/lib/css_modules/basic2@title') do |name, path|
        yielded << [name, path]
      end

      assert_match(/^title_[a-z0-9]{8}_lib-css_modules-basic2-module$/, yielded.first.first)
      assert_equal '/lib/css_modules/basic2.module.css', yielded.first.last
    end

    it 'yields a nil side_load_path for plain class names with require_prefix: true' do
      yielded = []
      transformer.class_names(:title) { |_name, path| yielded << path }

      assert_equal [nil], yielded
    end

    it 'yields the source path for plain class names with require_prefix: false' do
      yielded = []
      transformer.class_names(:title, require_prefix: false) do |name, path|
        yielded << [name, path]
      end

      assert_equal 1, yielded.length
      assert_match(/^title_[a-z0-9]{8}_lib-css_modules-basic-module$/, yielded.first.first)
      assert_equal '/lib/css_modules/basic.module.css', yielded.first.last
    end

    it 'yields the same path string that Importer.import received' do
      Proscenium::Importer.reset

      transformer.class_names('/lib/css_modules/basic2@title') do |_name, path|
        assert_includes Proscenium::Importer.imported.keys, path
      end
    end

    it 'yields for every input name and preserves order' do
      yielded = []
      transformer.class_names(:@title, :plain, '/lib/css_modules/basic2@subtitle') do |name, path|
        yielded << [name, path]
      end

      assert_equal 3, yielded.length
      assert_match(/^title_[a-z0-9]{8}_/, yielded[0].first)
      assert_equal '/lib/css_modules/basic.module.css', yielded[0].last
      assert_equal ['plain', nil], yielded[1]
      assert_match(/^subtitle_[a-z0-9]{8}_/, yielded[2].first)
      assert_equal '/lib/css_modules/basic2.module.css', yielded[2].last
    end
  end
end
