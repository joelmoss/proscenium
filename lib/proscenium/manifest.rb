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

          outpath = fs_path(outpath).delete_prefix "#{public_path}/"

          ep = fs_path(details['entryPoint'])
          ep = if (gem = BundledGems.paths.find { |_, v| ep.start_with? "#{v}/" })
                 "@rubygems/#{gem[0]}#{ep.delete_prefix(gem[1])}"
               else
                 ep.delete_prefix(Rails.root.to_s)
               end

          manifest[ep] = [
            "/#{outpath}",
            details['cssBundle'] && fs_path(details['cssBundle']).delete_prefix(public_path)
          ].compact
        end
      end

      manifest
    end

    # esbuild records absolute paths in the metafile in the form the platform produced. Left in
    # Windows form, every delete_prefix above failed, the manifest was keyed by full Windows
    # paths, and every lookup missed: the app served source paths instead of the digest URLs it
    # had just compiled, silently.
    def fs_path(path) = Utils.fs_path(path)

    def reset!
      self.manifest = {}
      self.loaded = false
    end

    def [](key)
      loaded? ? manifest[key] : nil
    end
  end
end
