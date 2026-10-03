# frozen_string_literal: true

module Proscenium
  module Manifest
    mattr_accessor :manifest, default: {}

    module_function

    def load!
      public_path = Rails.configuration.paths['public'].first
      self.manifest = {}

      if Proscenium.config.manifest_path.exist?
        JSON.parse(Proscenium.config.manifest_path.read)['outputs'].each do |outpath, details|
          next if !details.key?('entryPoint')

          outpath = fs_path(outpath).delete_prefix "#{public_path}/"

          ep = fs_path(details['entryPoint'])
          ep = BundledGems.virtual_path(ep) || ep.delete_prefix(Rails.root.to_s)

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

    # Empty, not nil or a lazy re-read: the runtime daemon relies on a reset manifest staying
    # empty until `load!`.
    def reset!
      self.manifest = {}
    end

    def [](key) = manifest[key]
  end
end
