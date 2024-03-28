# frozen_string_literal: true

class UILayout < ApplicationLayout
  def page_title
    'Proscenium:UI'
  end

  def around_template(&block)
    super do
      header do
        div class: :logo do
          a(href: :ui) { img src: '/logo.svg', width: 130, height: 27 }
        end
        render Proscenium::UI::Breadcrumbs::Component.new with_home: false
      end

      div class: :columned do
        main(&block)
        div(class: :page_nav) { page_nav } if respond_to?(:page_nav, true)
      end
    end
  end
end
