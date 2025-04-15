# frozen_string_literal: true

require 'gems'

class Proscenium::Registry
  class RubyGemPackage < Package
    def version = spec['version']

    private

    def package_json
      @package_json ||= begin
        package_path = Proscenium::RubyGems.path_for(gem_name, version).join('package.json')
        if package_path.exist?
          JSON.parse path.read
        else
          default_package_json
        end
      end
    end

    def spec
      @spec ||= if @version.present?
                  Gems::V2.info gem_name, @version
                else
                  Gems.info(gem_name)
                end
    end
  end
end
