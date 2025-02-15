# frozen_string_literal: true

require 'rubygems/package'

class PackagesController < ActionController::API
  rescue_from Gems::NotFound, with: :render_not_found
  before_action :validate_package

  def index = render json: {}

  # 1. Fetch the gem metadata from RubyGems API
  #   https://rubygems.org/api/v2/rubygems/GEM/versions/VERSION.json for a specific version,
  #   https://rubygems.org/api/v1/versions/GEM/latest.json to get latest version number.
  # 2. Extract the dependencies from the response, via the `metadata.npm_dependencies` key.
  # 3. Create an empty tarball, which will be downloaded by the npm client, and unpacked into
  #    node_modules. Proscenium ignores this, as it will pull contents directly from location of the
  #    installed gem.
  # 4. Return a valid npm response listing package details, tarball location, and its dependencies.
  def show
    render json: {
      name: package_name,
      'dist-tags': {
        latest: package_version
      },
      versions: {
        "#{package_version}": {
          name: package_name,
          version: package_version,
          dependencies: gem_data['metadata']['npm_dependencies'] || {},
          dist: {
            tarball:,
            integrity:,
            shasum:
          }
        }
      }
    }
  end

  private

  def validate_package
    return if package_name.start_with?('@rubygems/')

    render_not_found('Package not found; only Ruby gems are currently supported, and via the ' \
                     '@rubygems scope.') and return
  end

  def gem_name
    @gem_name ||= package_name.gsub('@rubygems/', '')
  end

  def package_name = params[:package]
  def package_version = gem_data['version']

  def gem_data
    @gem_data ||= if params[:version].present?
                    Gems::V2.info gem_name, params[:version]
                  else
                    Gems.info(gem_name)
                  end
  end

  def tarball
    create_tarball unless tarball_path.exist?

    relative_path = tarball_path.relative_path_from(Rails.public_path)
    "#{request.protocol}#{request.host_with_port}/#{relative_path}"
  end

  def tarball_name
    @tarball_name ||= "#{gem_name}-#{package_version}"
  end

  def tarball_path
    @tarball_path ||= Rails.public_path.join("tarballs/@rubygems/#{gem_name}/#{tarball_name}.tgz")
  end

  def shasum = Digest::SHA1.file(tarball_path).hexdigest
  def integrity = "sha512-#{Digest::SHA512.file(tarball_path).base64digest}"

  def create_tarball
    FileUtils.mkdir_p(File.dirname(tarball_path))

    File.open(tarball_path, 'wb') do |file|
      Zlib::GzipWriter.wrap(file) do |gz|
        Gem::Package::TarWriter.new(gz) do |tar|
          pjson = '{}'
          tar.add_file_simple('package/package.json', 0o444, pjson.length) do |io|
            io.write pjson
          end
        end
      end
    end
  end

  def render_not_found(message = 'Not found')
    render json: { error: message }, status: :not_found
  end
end
