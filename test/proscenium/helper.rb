# frozen_string_literal: true

describe Proscenium::Helper do
  def before
    Proscenium::Importer.reset
    Proscenium::Resolver.reset
  end

  attr_reader :page

  def render(output)
    @page = Capybara::Node::Simple.new(output)
  end

  describe '#css_module' do
    it 'transforms class names beginning with @' do
      render CssmHelperController.render :index

      expect(page.has_css?('body.body-ead1b5bc')).to be == true
      expect(page.has_css?('h2.view-ba1ab2b7')).to be == true
      expect(page.has_css?('div.partial-7800dcdf.world')).to be == true
    end
  end
end
