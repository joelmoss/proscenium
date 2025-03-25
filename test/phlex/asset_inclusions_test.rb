# frozen_string_literal: true

class Proscenium::Phlex::AssetInclusionsTest < ActionDispatch::IntegrationTest
  describe '#include_assets' do
    context 'controller is false; view is true' do
      it 'includes side loaded assets' do
        get '/phlex/include_assets'

        assert_dom 'link[rel="stylesheet"][href="/app/views/layouts/basic_layout.css"]'
        assert_dom 'link[rel="stylesheet"][href="/app/views/phlex/include_assets_view.css"]'
        assert_dom 'script[src="/app/views/phlex/include_assets_view.js"]'
      end
    end
  end
end
