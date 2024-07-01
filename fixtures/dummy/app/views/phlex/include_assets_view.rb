# frozen_string_literal: true

class Phlex::IncludeAssetsView < BasicLayout
  sideload_assets true

  def view_template
    include_assets
    h1 { 'Hello' }
  end
end
