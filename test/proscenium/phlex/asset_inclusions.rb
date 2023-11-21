# frozen_string_literal: true

require 'system_testing'
require 'phlex/testing/rails/view_helper'
require 'phlex/testing/capybara'

describe Proscenium::Phlex::AssetInclusions do
  def before
    Proscenium::Importer.reset
    Proscenium::Resolver.reset
  end

  describe '#include_assets' do
    include_context SystemTest

    with 'controller is false; view is true' do
      it 'includes side loaded assets' do
        visit '/phlex/include_assets'

        expect(page.html).to include(
          '<head>' \
          '<link rel="stylesheet" href="/app/views/phlex/include_assets.css">' \
          '<script src="/app/views/phlex/include_assets.js"></script>' \
          '</head>'
        )
      end
    end
  end
end
