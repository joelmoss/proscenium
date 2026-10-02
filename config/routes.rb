# frozen_string_literal: true

Proscenium::Railtie.routes.draw do
  scope path: :registry, controller: :registry, defaults: { format: 'json' } do
    get '', action: :index
    # npm's own tarball URL, so ahead of the package it would otherwise match.
    get '@rubygems/:gem/-/:file', action: :tarball, as: :tarball, format: false,
                                  constraints: { gem: /[\w-]+/, file: %r{[^/]+} }
    get '*package', action: :show, package: /.+/
  end
end
