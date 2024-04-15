# frozen_string_literal: true

class Phlex::NestedSideLoadView < Phlex::SideLoadView
  def view_template
    super do
      div { 'world' }
    end
  end
end
