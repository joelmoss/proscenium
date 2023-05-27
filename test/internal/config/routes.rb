# frozen_string_literal: true

Rails.application.routes.draw do
  root to: 'pages#home'

  get 'phlex/react/one', to: 'phlex/react#one'

  get 'first_component', to: 'pages#first_component'
  get 'first_react_component', to: 'pages#first_react_component'
  get 'second_react_component', to: 'pages#second_react_component'
  get 'action_rendered_component', to: 'pages#action_rendered_component'

  get 'phlex/basic', to: 'phlex#basic'
end
