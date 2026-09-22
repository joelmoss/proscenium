# frozen_string_literal: true

require 'test_helper'
require 'tmpdir'

class Proscenium::ManifestTest < ActiveSupport::TestCase
  # esbuild records absolute paths in the metafile in whatever form the platform produced. On
  # Windows that is backslashes, while everything `load!` matches them against - Rails.root, the
  # public path - is slash-form, so every prefix strip failed and the manifest ended up keyed by
  # full Windows paths. Nothing raised: lookups simply missed, and the app served the source path
  # instead of the digest URL it had just compiled.
  #
  # Written from a fixture rather than by compiling, so it runs on every platform: the conversion
  # is Windows-only, so `Gem.win_platform?` is the thing being varied.
  describe '.load! with a metafile written by Windows' do
    def write_manifest(entry_point, out_path)
      dir = Pathname.new(Dir.mktmpdir('manifest'))
      path = dir.join('.manifest.json')
      css = out_path.sub(/\.js\z/, '.css')
      path.write({ outputs: { out_path => { entryPoint: entry_point, cssBundle: css } } }.to_json)
      [dir, path]
    end

    around do |test|
      @dir, path = write_manifest(
        "#{Rails.root.to_s.tr('/', '\\')}\\app\\components\\x.js",
        "#{Rails.root.to_s.tr('/', '\\')}\\public\\assets\\app\\components\\x-$ABC123$.js"
      )
      orig = Proscenium.config.manifest_path
      Proscenium.config.manifest_path = path
      test.call
    ensure
      Proscenium.config.manifest_path = orig
      Proscenium::Manifest.reset!
      FileUtils.rm_rf(@dir) if @dir
    end

    it 'keys the entry point by its root-relative URL path' do
      as_platform(true) { Proscenium::Manifest.load! }

      assert_equal ['/assets/app/components/x-$ABC123$.js',
                    '/assets/app/components/x-$ABC123$.css'],
                   Proscenium::Manifest['/app/components/x.js']
    end

    # The same fixture without the conversion, which is what every platform saw before: the key
    # keeps the whole Windows path, so the lookup above finds nothing.
    it 'cannot key it at all when the paths are left in Windows form' do
      as_platform(false) { Proscenium::Manifest.load! }

      assert_nil Proscenium::Manifest['/app/components/x.js']
    end
  end
end
