# frozen_string_literal: true

Rails.application.routes.draw do
  get 'ui' => 'ui#index'
  namespace :ui do
    get :breadcrumbs, to: 'breadcrumbs#index'

    get :form, to: 'form#index'
    namespace :form do
      get 'text_field'
      get 'file_field'
      get 'url_field'
      get 'email_field'
      get 'number_field'
      get 'time_field'
      get 'date_field'
      get 'datetime_local_field'
      get 'week_field'
      get 'month_field'
      get 'color_field'
      get 'search_field'
      get 'password_field'
      get 'range_field'
      get 'tel_field'
      get 'checkbox_field'
      get 'select_field'
      get 'radio_group'
      get 'radio_field'
      get 'textarea_field'
      get 'rich_textarea_field'
      get 'hidden_field'
    end

    get :ujs, to: 'ujs#index'
    namespace :ujs do
      get 'disable_with'
      get 'confirm'
    end
  end

  scope defaults: { format: 'json' }, constraints: { subdomain: 'registry' } do
    get '' => 'packages#index'
    get ':package(/:version)' => 'packages#show', package: %r{[^/]+(/[^/]+)?}, version: %r{[^/]+}
  end

  # Fixture routes
  get 'users' => 'users#new'

  root to: 'pages#index'
end
