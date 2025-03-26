# frozen_string_literal: true

class Proscenium::Registry
  # 1. Fetch the gem metadata from RubyGems API.
  # 2. Extract any package.json from the gem, and populate the response with it.
  # 3. Create a tarball containing the fetched package.json. This will be downloaded by the npm
  #    client, and unpacked into node_modules. Proscenium ignores this, as it will pull contents
  #    directly from location of the installed gem.
  # 4. Return a valid npm response listing package details, tarball location, and its dependencies.
  #
  # See https://wiki.commonjs.org/wiki/Packages/Registry
  class Package
    extend Literal::Properties

    prop :name, String, :positional, reader: :private
    prop :version, _String?
    prop :host, String

    def as_json
      {
        name:,
        'dist-tags': {
          latest: version
        },
        versions: {
          version => {
            name:,
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

    def validate!
      return self if name.start_with?('@rubygems/')

      raise PackageUnsupportedError, name
    end

    def gem_name = @gem_name ||= name.gsub('@rubygems/', '')
    def version = @version # rubocop:disable Style/TrivialAccessors
    def shasum = Digest::SHA1.file(tarball_path).hexdigest
    def integrity = "sha512-#{Digest::SHA512.file(tarball_path).base64digest}"

    private

    def tarball
      create_tarball unless tarball_path.exist?

      "#{@host}/#{tarball_path.relative_path_from(Rails.public_path)}"
    end

    def tarball_name
      @tarball_name ||= "#{gem_name}-#{version}"
    end

    def tarball_path
      @tarball_path ||= Rails.public_path.join("tarballs/@rubygems/#{gem_name}/#{tarball_name}.tgz")
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
      @package_json ||= default_package_json
    end

    def default_package_json
      {
        name:,
        version:,
        dependencies: {}
      }
    end
  end
end
