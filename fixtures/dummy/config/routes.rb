Rails.application.routes.draw do
  # Tests
  root to: 'bare_pages#home'
  get '/phlex/react/one', to: 'phlex/react#one'
  get '/phlex/react/lazy', to: 'phlex/react#lazy'
  get '/phlex/react/forward_children', to: 'phlex/react#forward_children'

  get '/include_assets', to: 'bare_pages#include_assets'
  get '/phlex/include_assets', to: 'phlex#include_assets'

  # get '/sideloadpartial', to: 'pages#sideloadpartial'
  # get '/variant', to: 'pages#variant'
  # get '/external_gem', to: 'pages#external_gem'
  # get 'phlex/basic', to: 'phlex#basic'
  # get 'first_component', to: 'pages#first_component'
  # get 'first_react_component', to: 'pages#first_react_component'
  # get 'second_react_component', to: 'pages#second_react_component'

  # Playground
  resources :articles
end
