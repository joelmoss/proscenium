# frozen_string_literal: true

class Phlex::IncludeAssetsView < Proscenium::Phlex
  sideload_assets true

  def view_template
    include_assets
    h1 { 'Hello' }
  end
end
