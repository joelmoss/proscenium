# frozen_string_literal: true

require 'test_helper'

class Proscenium::CssModule::TransformerTest < ActiveSupport::TestCase
  describe '#class_names' do
    it 'transforms class names beginning with @' do
      names = Proscenium::CssModule::Transformer.class_names('/lib/css_modules/basic', :@title)

      assert_equal [['title-c3f452b4', '/lib/css_modules/basic.module.css']], names
    end

    it 'transforms class names beginning with @ and underscore' do
      names = Proscenium::CssModule::Transformer.class_names('/lib/css_modules/basic', :@_title)

      assert_equal [['_title-c3f452b4', '/lib/css_modules/basic.module.css']], names
    end

    it 'passes through regular class names' do
      names = Proscenium::CssModule::Transformer.class_names('/lib/css_modules/basic', :title)

      assert_equal ['title'], names
    end

    it 'accepts multiple names' do
      names = Proscenium::CssModule::Transformer.class_names('/lib/css_modules/basic',
                                                             :title, :@subtitle)

      assert_equal ['title', ['subtitle-c3f452b4', '/lib/css_modules/basic.module.css']], names
    end

    it 'imports stylesheet' do
      Proscenium::CssModule::Transformer.class_names('/lib/css_modules/basic', :@title)

      assert_equal({
                     '/lib/css_modules/basic.module.css' => { digest: 'c3f452b4' }
                   }, Proscenium::Importer.imported)
    end

    context 'local path' do
      it 'transforms class names' do
        names = Proscenium::CssModule::Transformer.class_names('/lib/css_modules/basic',
                                                               '/lib/css_modules/basic2@title',
                                                               :@subtitle)

        assert_equal [['title-6fd80271', '/lib/css_modules/basic2.module.css'],
                      ['subtitle-c3f452b4', '/lib/css_modules/basic.module.css']], names
      end

      it 'imports stylesheets' do
        Proscenium::CssModule::Transformer.class_names('/lib/css_modules/basic',
                                                       '/lib/css_modules/basic2@title', :@subtitle)

        assert_equal({
                       '/lib/css_modules/basic2.module.css' => { digest: '6fd80271' },
                       '/lib/css_modules/basic.module.css' => { digest: 'c3f452b4' }
                     }, Proscenium::Importer.imported)
      end
    end

    context 'npm package path' do
      it 'transforms class names' do
        names = Proscenium::CssModule::Transformer.class_names('/lib/css_modules/basic',
                                                               'pkg/one@pkg_one_module')

        assert_equal [
          ['pkg_one_module-5b960aa1', '/node_modules/pkg/one.module.css']
        ],
                     names
      end

      it 'imports stylesheets' do
        Proscenium::CssModule::Transformer.class_names('/lib/css_modules/basic',
                                                       'pkg/one@pkg_one_module')

        assert_equal({
                       '/node_modules/pkg/one.module.css' => { digest: '5b960aa1' }
                     }, Proscenium::Importer.imported)
      end
    end

    context 'gem path' do
      it 'transforms class names' do
        names = Proscenium::CssModule::Transformer.class_names('/lib/css_modules/basic',
                                                               '/gem2/lib/gem2/styles@foo')

        assert_equal [['foo-a074d644', '/gem2/lib/gem2/styles.module.css']], names
      end

      it 'imports stylesheets' do
        Proscenium::CssModule::Transformer.class_names('/lib/css_modules/basic',
                                                       '/gem2/lib/gem2/styles@@foo')

        assert_equal({
                       '/gem2/lib/gem2/styles.module.css' => { digest: 'a074d644' }
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

        assert_equal [['title-6fd80271', '/lib/css_modules/basic2.module.css']], names
      end

      it 'should transform npm path' do
        names = transformer.class_names('pkg/one@pkg_one_module')

        assert_equal [['pkg_one_module-5b960aa1', '/node_modules/pkg/one.module.css']], names
      end

      it 'should transform gem path' do
        names = transformer.class_names('/gem2/lib/gem2/styles@foo')

        assert_equal [['foo-a074d644', '/gem2/lib/gem2/styles.module.css']], names
      end
    end
  end
end
