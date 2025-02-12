# frozen_string_literal: true

module Proscenium::UI
  class Flash < Component
    register_element :pui_flash

    def self.source_path
      super / '../flash/index.rb'
    end

    def view_template
      pui_flash data: { flash: helpers.flash.to_hash }
    end
  end
end
