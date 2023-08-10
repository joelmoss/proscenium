Rails.application.routes.draw do
  # Tests
  root to: 'pages#home'
  get '/sideloadpartial', to: 'pages#sideloadpartial'
  get '/variant', to: 'pages#variant'
  get '/vendored_gem', to: 'pages#vendored_gem'
  get '/external_gem', to: 'pages#external_gem'
  get 'phlex/react/one', to: 'phlex/react#one'
  get 'phlex/basic', to: 'phlex#basic'
  get 'first_component', to: 'pages#first_component'
  get 'first_react_component', to: 'pages#first_react_component'
  get 'second_react_component', to: 'pages#second_react_component'

  # Playground
  resources :articles
end
