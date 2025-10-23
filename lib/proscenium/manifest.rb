# frozen_string_literal: true

module Proscenium
  module Manifest
    mattr_accessor :manifest, default: {}
    mattr_accessor :loaded, default: false

    module_function

    def loaded?
      loaded
    end

    def load!
      self.manifest = {}
      self.loaded = false

      if Proscenium.config.manifest_path.exist?
        self.loaded = true

        JSON.parse(Proscenium.config.manifest_path.read)['outputs'].each do |output_path, details|
          next if !details.key?('entryPoint')

          manifest[details['entryPoint']] = "/#{output_path.delete_prefix('public/')}"
        end
      end

      manifest
    end

    def reset!
      self.manifest = {}
      self.loaded = false
    end

    def [](key)
      loaded? ? manifest[key] : "/#{key}"
    end
  end
end
