# frozen_string_literal: true

require 'rubygems/package'

# Controller that serves a local NPM-compatible registry as part of the Rails app that depends
# on Proscenium. It serves packages that are backed by Ruby gems in the app's bundle. If a
# package.json is present in the root of a gem, that will be used. Otherwise, a minimal one is
# generated based on the gem's name and version.
#
# This allows frontend assets (JS, CSS, etc.) to be distributed as part of Ruby gems, simplifying
# dependency management for Rails applications that use both Ruby and JavaScript libraries. And by
# serving the packages via a local registry, it avoids the need to publish them to a public NPM
# registry. When you install a package from this registry, it will also resolve any dependencies
# specified in the package.json file. Just as you would expect if you were installing from a real
# NPM registry.
#
# Note that this should only be used for local development and testing purposes. It will also only
# serve gems that you have installed in your bundle; it does not proxy requests to a real NPM
# registry. It will raise a `GemNotInstalledError` error if you try to request a package for a gem
# that is not installed.
#
# Assuming you have a Rails app that includes Proscenium, and it is running (`rails server`), you
# can configure your NPM/Yarn client to use this registry by adding the following to your `.npmrc`
# or `.yarnrc` file:
#
# ```ini
# @rubygems:registry=http://localhost:3000/proscenium/registry/
# ```
#
# (replace `http://localhost:3000` with the appropriate host and port for your Rails app)
#
# Then, you can install packages from Ruby gems in your bundle using commands like:
#
# ```bash
# npm install @rubygems/my-ruby-gem
# pnpm add @rubygems/my-ruby-gem
# yarn add @rubygems/my-ruby-gem
# ```
#
# The packages must be namespaced under the `@rubygems` scope to avoid conflicts with real NPM
# packages.
class Proscenium::RegistryController < ActionController::Base
  class PackageNotFoundError < Proscenium::Error
    def initialize(name)
      super(<<-TEXT)
        Package `#{name}` is not valid, or does not exist; only Ruby gems are supported via the
        @rubygems scope.
      TEXT
    end
  end

  class GemNotInstalledError < Proscenium::Error
    def initialize(name)
      super("Package `#{name}` is not found in your bundle; have you installed the Ruby gem?")
    end
  end

  rescue_from PackageNotFoundError, with: :render_not_found
  rescue_from GemNotInstalledError, with: :render_not_found

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

  # TODO: include shasum and integrity in the tarball URL to allow caching, and ensure uniqueness.
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
        raise GemNotInstalledError, @gem_name
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
