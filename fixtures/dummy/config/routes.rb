# frozen_string_literal: true

Rails.application.routes.draw do
  root to: 'bare_pages#home'

  get '/include_assets', to: 'bare_pages#include_assets'

  resources :users
  # get '/users' => 'users#index'
  # get '/user' => 'users#show'
  get '/events' => 'users#index'

  # get '/sideloadpartial', to: 'pages#sideloadpartial'
  # get '/variant', to: 'pages#variant'
  # get 'first_component', to: 'pages#first_component'
  # get 'first_react_component', to: 'pages#first_react_component'
  # get 'second_react_component', to: 'pages#second_react_component'
end
