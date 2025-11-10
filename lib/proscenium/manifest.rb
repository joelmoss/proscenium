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
      public_path = Rails.configuration.paths['public'].first
      self.manifest = {}
      self.loaded = false

      if Proscenium.config.manifest_path.exist?
        self.loaded = true

        JSON.parse(Proscenium.config.manifest_path.read)['outputs'].each do |outpath, details|
          next if !details.key?('entryPoint')

          outpath = outpath.delete_prefix "#{public_path}/"

          ep = details['entryPoint']
          ep = if (gem = BundledGems.paths.find { |_, v| ep.start_with? "#{v}/" })
                 "@rubygems/#{gem[0]}#{ep.delete_prefix(gem[1])}"
               else
                 ep.delete_prefix(Rails.root.to_s)
               end

          manifest[ep] = "/#{outpath}"
        end
      end

      manifest
    end

    def reset!
      self.manifest = {}
      self.loaded = false
    end

    def [](key)
      loaded? ? manifest[key] : nil
    end
  end
end
