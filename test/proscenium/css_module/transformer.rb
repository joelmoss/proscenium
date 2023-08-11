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
    with 'unknown stylesheet' do
      it 'raise StylesheetNotFound' do
        expect do
          Proscenium::CssModule::Transformer.class_names('/foo', :@title)
        end.to raise_exception(Proscenium::CssModule::StylesheetNotFound)
      end
    end

    it 'transforms class names beginning with @' do
      names = Proscenium::CssModule::Transformer.class_names('/lib/css_modules/basic', :@title)

      expect(names).to be == ['titlec3f452b4']
    end

    it 'transforms class names beginning with @ and underscore' do
      names = Proscenium::CssModule::Transformer.class_names('/lib/css_modules/basic', :@_title)

      expect(names).to be == ['_titlec3f452b4']
    end

    it 'passes through regular class names' do
      names = Proscenium::CssModule::Transformer.class_names('/lib/css_modules/basic', :title)

      expect(names).to be == ['title']
    end

    it 'accepts multiple names' do
      names = Proscenium::CssModule::Transformer.class_names('/lib/css_modules/basic', :title, :@subtitle)

      expect(names).to be == %w[title subtitlec3f452b4]
    end

    it 'accepts local path' do
      names = Proscenium::CssModule::Transformer.class_names('/lib/css_modules/basic', '/lib/css_modules/basic2@title', :@subtitle)

      expect(names).to be == %w[title6fd80271 subtitlec3f452b4]
    end
  end
end
