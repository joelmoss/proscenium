# frozen_string_literal: true

Proscenium::Railtie.routes.draw do
  scope path: :packages, controller: :packages, defaults: { format: 'json' } do
    get '', action: 'index'
    get ':package(/:version)', action: 'show', package: %r{[^/]+(/[^/]+)?}, version: %r{[^/]+}
  end
end
