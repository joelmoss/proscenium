# frozen_string_literal: true

module UI
  class UJSController < UIController
    add_breadcrumb 'UJS', :ui_ujs

    def index
      render UJS::IndexView.new
    end

    def confirm
      add_breadcrumb 'confirm'
    end

    def disable_with
      add_breadcrumb 'disable_with'
    end
  end
end
