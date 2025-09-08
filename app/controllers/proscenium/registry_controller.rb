# frozen_string_literal: true

require 'rubygems/package'

class Proscenium::RegistryController < ActionController::Base
  class PackageNotFoundError < StandardError
    def initialize(name)
      super(<<-TEXT)
        Package `#{name}` is not valid, or does not exist; only Ruby gems are supported via the
        @rubygems scope.
      TEXT
    end
  end

  class PackageNotInstalledError < StandardError
    def initialize(name)
      super("Package `#{name}` is not found in your bundle; have you installed the Ruby gem?")
    end
  end

  rescue_from PackageNotFoundError, with: :render_not_found
  rescue_from PackageNotInstalledError, with: :render_not_found

  def index
    render json: {}
  end

  def show
    @gem_name, @version = package_params

    render json: {
      name: full_name,
      'dist-tags': {
        latest: version
      },
      versions: {
        version => {
          name: full_name,
          version:,
          dependencies: package_json['dependencies'] || {},
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

  def render_not_found(message = 'Not found')
    render json: { error: message }, status: :not_found
  end

  def package_params
    @package_params ||= params.expect(:package).then do |it| # rubocop:disable Style/ItAssignment
      unless (res = it.gsub('%2F', '/').match(%r{^@rubygems/([\w\-_]+)/?([\w\-._]+)?$}))
        raise PackageNotFoundError, it
      end

      [res[1], res[2]]
    end
  end

  def tarball
    create_tarball unless tarball_path.exist?

    host = "#{request.protocol}#{request.host_with_port}"
    "#{host}/#{tarball_path.relative_path_from(Rails.public_path)}"
  end

  def tarball_name
    @tarball_name ||= "#{@gem_name}-#{version}"
  end

  def tarball_path
    @tarball_path ||= Rails.public_path.join('proscenium_registry_tarballs')
                           .join("@rubygems/#{@gem_name}/#{tarball_name}.tgz")
  end

  def create_tarball
    FileUtils.mkdir_p(File.dirname(tarball_path))

    File.open(tarball_path, 'wb') do |file|
      Zlib::GzipWriter.wrap(file) do |gz|
        Gem::Package::TarWriter.new(gz) do |tar|
          contents = package_json.to_json
          tar.add_file_simple('package/package.json', 0o444, contents.length) do |io|
            io.write contents
          end
        end
      end
    end
  end

  def package_json
    @package_json ||= begin
      unless (gem_path = Proscenium::BundledGems.pathname_for(@gem_name))
        raise PackageNotInstalledError, @gem_name
      end

      if (package_path = gem_path.join('package.json')).exist?
        JSON.parse(package_path.read)
      else
        { name: @gem_name, version:, dependencies: {} }
      end
    end
  end

  def full_name = @full_name ||= "@rubygems/#{@gem_name}"
  def version = @version ||= spec.version.to_s
  def spec = @spec ||= Bundler.load.specs[@gem_name].first
  def shasum = Digest::SHA1.file(tarball_path).hexdigest
  def integrity = "sha512-#{Digest::SHA512.file(tarball_path).base64digest}"
end
