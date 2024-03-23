Rails.application.routes.draw do
  get 'ui' => 'ui#index'
  namespace :ui do
    get :breadcrumbs, to: 'breadcrumbs#index'
  end
  resources :articles
end
