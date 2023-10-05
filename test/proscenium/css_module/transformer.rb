# frozen_string_literal: true

describe Proscenium::CssModule::Transformer do
  def before
    Proscenium::Importer.reset
    Proscenium::Resolver.reset
  end

  attr_reader :page

  def render(output)
    @page = Capybara::Node::Simple.new(output)
  end

  describe '#class_names' do
    it 'transforms class names beginning with @' do
      names = Proscenium::CssModule::Transformer.class_names('/lib/css_modules/basic', :@title)

      expect(names).to be == ['title-c3f452b4']
    end

    it 'transforms class names beginning with @ and underscore' do
      names = Proscenium::CssModule::Transformer.class_names('/lib/css_modules/basic', :@_title)

      expect(names).to be == ['_title-c3f452b4']
    end

    it 'passes through regular class names' do
      names = Proscenium::CssModule::Transformer.class_names('/lib/css_modules/basic', :title)

      expect(names).to be == ['title']
    end

    it 'accepts multiple names' do
      names = Proscenium::CssModule::Transformer.class_names('/lib/css_modules/basic', :title, :@subtitle)

      expect(names).to be == %w[title subtitle-c3f452b4]
    end

    it 'imports stylesheet' do
      Proscenium::CssModule::Transformer.class_names('/lib/css_modules/basic', :@title)

      expect(Proscenium::Importer.imported).to be == {
        '/lib/css_modules/basic.module.css' => { digest: 'c3f452b4' }
      }
    end

    with 'local path' do
      it 'transforms class names' do
        names = Proscenium::CssModule::Transformer.class_names('/lib/css_modules/basic',
                                                               '/lib/css_modules/basic2@title', :@subtitle)

        expect(names).to be == %w[title-6fd80271 subtitle-c3f452b4]
      end

      it 'imports stylesheets' do
        Proscenium::CssModule::Transformer.class_names('/lib/css_modules/basic',
                                                       '/lib/css_modules/basic2@title', :@subtitle)

        expect(Proscenium::Importer.imported).to be == {
          '/lib/css_modules/basic2.module.css' => { digest: '6fd80271' },
          '/lib/css_modules/basic.module.css' => { digest: 'c3f452b4' }
        }
      end
    end

    with 'npm package path' do
      it 'transforms class names' do
        names = Proscenium::CssModule::Transformer.class_names('/lib/css_modules/basic',
                                                               'mypackage/foo@foo')

        expect(names).to be == %w[foo-39337ba7]
      end

      it 'imports stylesheets' do
        Proscenium::CssModule::Transformer.class_names('/lib/css_modules/basic', 'mypackage/foo@foo')

        expect(Proscenium::Importer.imported).to be == {
          '/packages/mypackage/foo.module.css' => { digest: '39337ba7' }
        }
      end
    end

    with 'gem path' do
      it 'transforms class names' do
        names = Proscenium::CssModule::Transformer.class_names('/lib/css_modules/basic',
                                                               '/gem2/lib/gem2/styles@foo')

        expect(names).to be == %w[foo-a074d644]
      end

      it 'imports stylesheets' do
        Proscenium::CssModule::Transformer.class_names('/lib/css_modules/basic',
                                                       '/gem2/lib/gem2/styles@@foo')

        expect(Proscenium::Importer.imported).to be == {
          '/gem2/lib/gem2/styles.module.css' => { digest: 'a074d644' }
        }
      end
    end
  end

  describe '.class_names' do
    with 'given path is nil' do
      let(:transformer) { Proscenium::CssModule::Transformer.new(nil) }

      it 'should raise when transforming class with leading @' do
        expect do
          transformer.class_names(:@title)
        end.to raise_exception Proscenium::CssModule::TransformError
      end

      it 'should transform regular class' do
        names = transformer.class_names(:title)

        expect(names).to be == ['title']
      end

      it 'should transform local path' do
        names = transformer.class_names('/lib/css_modules/basic2@title')

        expect(names).to be == ['title-6fd80271']
      end

      it 'should transform npm path' do
        names = transformer.class_names('mypackage/foo@foo')

        expect(names).to be == ['foo-39337ba7']
      end

      it 'should transform gem path' do
        names = transformer.class_names('/gem2/lib/gem2/styles@foo')

        expect(names).to be == ['foo-a074d644']
      end
    end
  end
end
