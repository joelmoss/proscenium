# frozen_string_literal: true

Rails.application.routes.draw do
  get 'ui' => 'ui#index'
  namespace :ui do
    get :breadcrumbs, to: 'breadcrumbs#index'

    get :ujs, to: 'ujs#index'
    namespace :ujs do
      get 'disable_with'
      get 'confirm'
    end
  end

  root to: 'pages#index'
end
