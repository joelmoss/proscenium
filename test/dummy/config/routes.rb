Rails.application.routes.draw do
  # mount Importmap::Engine => "/importmap"

  root to: 'pages#home'

  get '/typescript', to: 'pages#typescript'
  get '/sideloadpartial', to: 'pages#sideloadpartial'
  get '/variant', to: 'pages#variant'

  get 'phlex/react/one', to: 'phlex/react#one'
  get 'phlex/basic', to: 'phlex#basic'

  get 'first_component', to: 'pages#first_component'
  get 'first_react_component', to: 'pages#first_react_component'
  get 'second_react_component', to: 'pages#second_react_component'
  get 'action_rendered_component', to: 'pages#action_rendered_component'
end
