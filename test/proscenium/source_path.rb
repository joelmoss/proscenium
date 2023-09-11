# frozen_string_literal: true

require 'fixtures'

describe Proscenium::SourcePath do
  def before
    Proscenium::Importer.reset
    Proscenium::Resolver.reset
  end

  with 'view component' do
    it 'returns file system path to source file' do
      expect(ViewComponent::CssModule::Component.source_path).to be == Rails.root.join('app/components/view_component/css_module/component.rb')
    end
  end

  with 'phlex component' do
    it 'returns file system path to source file' do
      expect(Phlex::Plain.source_path).to be == Rails.root.join('app/components/phlex/plain.rb')
    end
  end
end
