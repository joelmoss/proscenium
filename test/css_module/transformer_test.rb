# frozen_string_literal: true

require 'test_helper'

class Proscenium::CssModule::TransformerTest < ActiveSupport::TestCase
  describe '#class_names' do
    it 'transforms class names beginning with @' do
      names = Proscenium::CssModule::Transformer.class_names('/lib/css_modules/basic', :@title)

      assert_match(/^title_[a-z0-9]{8}_lib-css_modules-basic-module$/, names.first)
    end

    it 'transforms class names beginning with @ and underscore' do
      names = Proscenium::CssModule::Transformer.class_names('/lib/css_modules/basic', :@_title)

      assert_match(/^_title_[a-z0-9]{8}_lib-css_modules-basic-module$/, names.first)
    end

    it 'passes through regular class names' do
      names = Proscenium::CssModule::Transformer.class_names('/lib/css_modules/basic', :title)

      assert_equal ['title'], names
    end

    it 'accepts multiple names' do
      names = Proscenium::CssModule::Transformer.class_names('/lib/css_modules/basic',
                                                             :title, :@subtitle)

      assert_equal 'title', names.first
      assert_match(/^subtitle_[a-z0-9]{8}_lib-css_modules-basic-module$/, names.last)
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

        assert_match(/^title_[a-z0-9]{8}_lib-css_modules-basic2-module$/, names.first)
        assert_match(/^subtitle_[a-z0-9]{8}_lib-css_modules-basic-module$/, names.last)
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

        assert_match(/^pkg_one_module_[a-z0-9]{8}_node_modules-pkg-one-module$/, names.first)
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

        assert_match(/^foo_[a-z0-9]{8}_gem2-lib-gem2-styles-module$/, names.first)
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
        names = transformer.class_names('/lib/css_modules/basic2@title')

        assert_match(/^title_[a-z0-9]{8}_lib-css_modules-basic2-module$/, names.first)
      end

      it 'should transform npm path' do
        names = transformer.class_names('pkg/one@pkg_one_module')

        assert_match(/^pkg_one_module_[a-z0-9]{8}_node_modules-pkg-one-module$/, names.first)
      end

      it 'should transform gem path' do
        names = transformer.class_names('/gem2/lib/gem2/styles@foo')

        assert_match(/^foo_[a-z0-9]{8}_gem2-lib-gem2-styles-module$/, names.first)
      end
    end
  end
end
