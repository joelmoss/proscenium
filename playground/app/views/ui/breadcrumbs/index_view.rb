# frozen_string_literal: true

class UI::Breadcrumbs::IndexView < UILayout
  def view_template
    h1 { 'Breadcrumbs' }

    section do
      h2(id: 'basic-usage') { 'Basic Usage' }

      p do
        plain 'First of all, include the Breadcrumbs control in your '
        code { 'ApplicationController' }
        plain ':'
      end

      render CodeBlockComponent.new :ruby do
        unsafe_raw <<~RUBY
          class ApplicationController < ActionController::Base
            include Proscenium::UI::Breadcrumbs::Control
          end
        RUBY
      end

      p do
        'Then render the breadcrumbs component in your view, or ideally your application layout:'
      end

      render CodeBlockComponent.new :ruby do
        <<~RUBY
          render Proscenium::UI::Breadcrumbs::Component.new
        RUBY
      end

      p do
        plain 'Then simply add your breadcrumbs with the '
        code { 'add_breadcrumb' }
        plain ' method:'
      end

      render CodeBlockComponent.new :ruby do
        unsafe_raw <<~RUBY
          class MyController < ApplicationController
            add_breadcrumb 'UI', :ui
            add_breadcrumb 'Breadcrumbs'
          end
        RUBY
      end

      render CodeStageComponent do
        render Proscenium::UI::Breadcrumbs::Component.new home_path: :ui
      end
    end
  end
end
