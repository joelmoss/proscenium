# frozen_string_literal: true

module Proscenium::Phlex::AssetInclusions
  def include_stylesheets
    comment { '[PROSCENIUM_STYLESHEETS]' }
  end

  def include_javascripts
    comment { '[PROSCENIUM_LAZY_SCRIPTS]' }
    comment { '[PROSCENIUM_JAVASCRIPTS]' }
  end

  def include_assets
    include_stylesheets
    include_javascripts
  end
end
