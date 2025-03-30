# frozen_string_literal: true

require 'rubygems/package'

class Proscenium::Registry
  class BundledPackage < Package
    def version = @version ||= spec.version.to_s

    private

    def package_json
      @package_json ||= begin
        unless (gem_path = Proscenium::BundledGems.pathname_for(gem_name))
          raise PackageNotInstalledError, name
        end

        if (package_path = gem_path.join('package.json')).exist?
          JSON.parse(package_path.read)
        else
          default_package_json
        end
      end
    end

    def spec
      @spec ||= Bundler.load.specs[gem_name].first
    end
  end
end
