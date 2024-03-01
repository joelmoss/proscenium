# frozen_string_literal: true

class Views::Phlex::IncludeAssets < Proscenium::Phlex
  sideload_assets true

  def template
    include_assets
    h1 { 'Hello' }
  end
end
