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
# registry. Each gem is served at the version in your bundle only. A gem that is not installed, or
# any other version of one that is, is answered with a 404.
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

  class VersionNotFoundError < Proscenium::Error
    def initialize(name, requested, installed)
      super("Package `#{name}` has no version `#{requested}`; your bundle has `#{installed}`.")
    end
  end

  class InvalidPackageJsonError < Proscenium::Error
    def initialize(name, reason)
      # A parser's reason quotes the bytes it choked on, which need not be UTF-8.
      super("Package `#{name}` has an invalid package.json: #{reason.scrub}")
    end
  end

  # Stamped with this, not Gem.source_date_epoch: in the RubyGems Ruby 3.4.0 ships, that is the
  # time each process started, and SOURCE_DATE_EPOCH overrides it on any version.
  TARBALL_MTIME = 315_619_200 # RubyGems' own default since 3.6.7

  rescue_from PackageNotFoundError, with: :render_not_found
  rescue_from GemNotInstalledError, with: :render_not_found
  rescue_from VersionNotFoundError, with: :render_not_found
  # A 4xx, as npm and pnpm retry a 5xx, and this will not fix itself.
  rescue_from InvalidPackageJsonError do |error|
    render json: { error: error.message }, status: 422
  end

  def index
    render json: {}
  end

  def show
    @gem_name, requested_version = package_params

    # Only the installed version exists, and `latest` - the one dist-tag advertised - names it.
    if requested_version && !['latest', version].include?(requested_version)
      raise VersionNotFoundError.new(full_name, requested_version, version)
    end

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
            tarball: tarball_url(gem: @gem_name, file: "#{@gem_name}-#{version}.tgz"),
            integrity: "sha512-#{Digest::SHA512.base64digest(tarball_data)}",
            shasum: Digest::SHA1.hexdigest(tarball_data)
          }
        }
      }
    }
  end

  # Built on every request rather than cached: the bytes are the same each time, so there is
  # nothing to go stale, and the URL a lockfile records works on a machine that never asked for
  # the packument, as `npm ci` and a frozen pnpm install do not.
  def tarball
    @gem_name = params[:gem]
    # Only npm's own name for the installed version's tarball, the one URL ever advertised.
    unless params[:file] == "#{@gem_name}-#{version}.tgz"
      requested = params[:file].delete_prefix("#{@gem_name}-").delete_suffix('.tgz')
      raise VersionNotFoundError.new(full_name, requested, version)
    end

    send_data tarball_data, type: 'application/octet-stream'
  end

  private

  def render_not_found(message = 'Not found')
    render json: { error: message }, status: :not_found
  end

  def package_params
    # Not `params.expect`, which Rails 7.2 does not have.
    @package_params ||= params.require(:package).then do |it| # rubocop:disable Style/ItAssignment
      unless (res = it.gsub('%2F', '/').match(%r{\A@rubygems/([\w\-_]+)/?([\w\-._]+)?\z}))
        raise PackageNotFoundError, it
      end

      [res[1], res[2]]
    end
  end

  # The same bytes every time for the same package.json, in any process and on any machine, so
  # the integrity a lockfile records holds across restarts, workers, operating systems and zlib
  # builds. The tar entry is framed here as the RubyGems Ruby 3.4.0 ships cannot give TarWriter
  # its time.
  def tarball_data
    @tarball_data ||= begin
      contents = package_json_contents
      header = Gem::Package::TarHeader.new(name: 'package/package.json', prefix: '', mode: 0o444,
                                           size: contents.bytesize, mtime: TARBALL_MTIME)
      # The entry padded to a whole 512 byte block, then the two empty blocks that end an archive.
      gzip header.to_s + contents + ("\0" * (-contents.bytesize % 512)) + ("\0" * 1024)
    end
  end

  # Framed by hand rather than with Zlib::GzipWriter, which writes the OS into the header, and
  # whose deflate output differs between zlib builds. Stored blocks hold the data as it is, so no
  # compressor is involved; a package.json is a few KB.
  def gzip(data)
    blocks = (0...data.bytesize).step(65_535).map { data.byteslice(it, 65_535) }
    deflate = blocks.each_with_index.map do |block, i|
      [i == blocks.size - 1 ? 1 : 0, block.bytesize, block.bytesize ^ 0xffff].pack('Cvv') + block
    end

    # Magic, deflate, no flags, the fixed time, no extra flags, and an unknown OS.
    [0x1f, 0x8b, 8, 0, TARBALL_MTIME, 0, 255].pack('C4VC2') + deflate.join +
      [Zlib.crc32(data), data.bytesize].pack('VV')
  end

  # The bytes packed: the gem's own package.json as written, less any byte order mark (npm strips
  # one too), so its integrity depends on the file alone, not on any JSON encoder. A gem without
  # one gets a minimal one. Checked here, so neither the packument nor the tarball is served for
  # one npm could not read.
  def package_json_contents
    @package_json_contents ||= begin
      contents = begin
        package_json_path.binread.delete_prefix("\uFEFF".b)
      rescue Errno::ENOENT
        # Only for a gem that has none. `exist?` is false for any file it cannot stat, which
        # would hide a broken symlink or a gem directory that has gone.
        raise unless package_json_path.dirname.directory? && !package_json_path.symlink?

        JSON.generate(name: @gem_name, version:, dependencies: {}).b
      end
      validate_package_json!(contents)
      contents
    rescue SystemCallError => e
      logger.error "#{package_json_path}: #{e.message}"
      # Not the message, which names the path.
      raise InvalidPackageJsonError.new(full_name, 'it cannot be read')
    end
  end

  def package_json = @package_json ||= JSON.parse(package_json_contents)

  # Plain JSON, as npm reads it: no comments, which Ruby's parser takes by default, and nothing
  # Rails' to_json would quietly change, such as a number too big for a float or a string that is
  # not UTF-8.
  def validate_package_json!(contents)
    json = JSON.parse(contents, allow_comments: false)
    raise JSON::ParserError, 'not an object' unless json.is_a?(Hash)

    JSON.generate(json)
  rescue JSON::JSONError => e
    logger.error "#{package_json_path}: #{e.message.scrub}"
    raise InvalidPackageJsonError.new(full_name, e.message)
  end

  def package_json_path
    @package_json_path ||= begin
      gem_path = Proscenium::BundledGems.pathname_for(@gem_name)
      raise GemNotInstalledError, @gem_name unless gem_path

      gem_path.join('package.json')
    end
  end

  def full_name = @full_name ||= "@rubygems/#{@gem_name}"
  def version = spec.version.to_s
  def spec = @spec ||= Bundler.load.specs[@gem_name].first || raise(GemNotInstalledError, @gem_name)
end
