# frozen_string_literal: true

Proscenium::Railtie.routes.draw do
  scope path: :registry, controller: :registry, defaults: { format: 'json' } do
    get '', action: :index
    get '*package', action: :show, package: /.+/
  end
end
