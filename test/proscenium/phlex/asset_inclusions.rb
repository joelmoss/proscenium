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
          '<link rel="stylesheet" href="/assets/app/views/phlex/include_assets$7T5XNBBO$.css">' \
          '<script src="/assets/app/views/phlex/include_assets$HZZYNYOW$.js"></script>' \
          '</head>'
        )
      end
    end
  end
end
