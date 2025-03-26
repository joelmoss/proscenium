# frozen_string_literal: true

class Proscenium::PackagesController < ActionController::Base
  rescue_from Proscenium::Registry::PackageUnsupportedError, with: :render_not_found
  rescue_from Proscenium::Registry::PackageNotInstalledError, with: :render_not_found

  def index
    render json: {}
  end

  def show
    host = "#{request.protocol}#{request.host_with_port}"
    render json: Proscenium::Registry.bundled_package(params[:package], host:).as_json
  end

  private

  def render_not_found(message = 'Not found')
    render json: { error: message }, status: :not_found
  end
end
