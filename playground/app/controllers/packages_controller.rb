# frozen_string_literal: true

require 'rubygems/package'

class PackagesController < ActionController::API
  rescue_from Proscenium::Registry::PackageUnsupportedError, with: :render_not_found
  rescue_from Gems::NotFound, with: :render_not_found

  def index = render json: {}

  def show
    host = "#{request.protocol}#{request.host_with_port}"
    render json: Proscenium::Registry.ruby_gem_package(params[:package], params[:version], host:)
                                     .as_json
  end

  private

  def render_not_found(message = 'Not found')
    render json: { error: message }, status: :not_found
  end
end
