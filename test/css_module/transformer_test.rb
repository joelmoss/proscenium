# frozen_string_literal: true

require 'test_helper'

class Proscenium::CssModule::TransformerTest < ActiveSupport::TestCase
  describe '#class_names' do
    it 'transforms class names beginning with @' do
      names = Proscenium::CssModule::Transformer.class_names('/lib/css_modules/basic', :@title)

      assert_equal ['title_3977965b'], names
    end

    it 'transforms class names beginning with @ and underscore' do
      names = Proscenium::CssModule::Transformer.class_names('/lib/css_modules/basic', :@_title)

      assert_equal ['_title_3977965b'], names
    end

    it 'passes through regular class names' do
      names = Proscenium::CssModule::Transformer.class_names('/lib/css_modules/basic', :title)

      assert_equal ['title'], names
    end

    it 'accepts multiple names' do
      names = Proscenium::CssModule::Transformer.class_names('/lib/css_modules/basic',
                                                             :title, :@subtitle)

      assert_equal %w[title subtitle_3977965b], names
    end

    it 'imports stylesheet' do
      Proscenium::CssModule::Transformer.class_names('/lib/css_modules/basic', :@title)

      assert_equal({
                     '/lib/css_modules/basic.module.css' => { digest: '3977965b' }
                   }, Proscenium::Importer.imported)
    end

    context 'local path' do
      it 'transforms class names' do
        names = Proscenium::CssModule::Transformer.class_names('/lib/css_modules/basic',
                                                               '/lib/css_modules/basic2@title',
                                                               :@subtitle)

        assert_equal %w[title_32581d4c subtitle_3977965b], names
      end

      it 'imports stylesheets' do
        Proscenium::CssModule::Transformer.class_names('/lib/css_modules/basic',
                                                       '/lib/css_modules/basic2@title', :@subtitle)

        assert_equal({
                       '/lib/css_modules/basic2.module.css' => { digest: '32581d4c' },
                       '/lib/css_modules/basic.module.css' => { digest: '3977965b' }
                     }, Proscenium::Importer.imported)
      end
    end

    context 'npm package path' do
      it 'transforms class names' do
        names = Proscenium::CssModule::Transformer.class_names('/lib/css_modules/basic',
                                                               'pkg/one@pkg_one_module')

        assert_equal ['pkg_one_module_f52a8541'], names
      end

      it 'imports stylesheets' do
        Proscenium::CssModule::Transformer.class_names('/lib/css_modules/basic',
                                                       'pkg/one@pkg_one_module')

        assert_equal({
                       '/node_modules/pkg/one.module.css' => { digest: 'f52a8541' }
                     }, Proscenium::Importer.imported)
      end
    end

    context 'gem path' do
      it 'transforms class names' do
        names = Proscenium::CssModule::Transformer.class_names('/lib/css_modules/basic',
                                                               '/gem2/lib/gem2/styles@foo')

        assert_equal ['foo_b0953e88'], names
      end

      it 'imports stylesheets' do
        Proscenium::CssModule::Transformer.class_names('/lib/css_modules/basic',
                                                       '/gem2/lib/gem2/styles@@foo')

        assert_equal({
                       '/gem2/lib/gem2/styles.module.css' => { digest: 'b0953e88' }
                     }, Proscenium::Importer.imported)
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

        assert_equal ['title_32581d4c'], names
      end

      it 'should transform npm path' do
        names = transformer.class_names('pkg/one@pkg_one_module')

        assert_equal ['pkg_one_module_f52a8541'], names
      end

      it 'should transform gem path' do
        names = transformer.class_names('/gem2/lib/gem2/styles@foo')

        assert_equal ['foo_b0953e88'], names
      end
    end
  end
end
