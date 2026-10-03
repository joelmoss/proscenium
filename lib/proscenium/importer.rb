# frozen_string_literal: true

require 'active_support/current_attributes'
require 'concurrent/map'

module Proscenium
  class Importer < ActiveSupport::CurrentAttributes
    JS_EXTENSIONS = %w[.tsx .ts .jsx .js].freeze
    CSS_EXTENSIONS = %w[.module.css .css].freeze

    # The readable suffix of a CSS module class name, by absolute path - or by URL, for a remote
    # module, which has no file. It is a pure function of that identity, but `import` runs once per
    # class name a view emits and `relative_path_from` is most of its cost, so it is built once per
    # file for the life of the process.
    SUFFIXES = Concurrent::Map.new

    # Holds the JS and CSS files to include in the current request.
    #
    # Example:
    #   {
    #     '/path/to/input/file.js': {
    #       output: '/path/to/compiled/file.js',
    #       **options
    #     }
    #   }
    attribute :imported

    class << self
      # Import the given `filepath`. This is idempotent - it will never include duplicates.
      #
      # @param filepath [String] Absolute URL path (relative to Rails root) of the file to import,
      #   or a URL, which has no file on disk. Should be the actual asset file, eg. app.css,
      #   some/component.js.
      # @return [String|nil] the digest of the imported file path if a css module (*.module.css).
      def import(filepath = nil, sideloaded: false, **)
        self.imported ||= {}

        if filepath.end_with?('.module.css')
          manifest_path, non_manifest_path, abs_path = Resolver.resolve(filepath, as_array: true)
          filepath = Array(manifest_path || non_manifest_path)[0]

          # A URL has no file on disk, so the URL is the module's identity. Taken after the
          # reassignment above, so the digest and the suffix cache below agree on it. An entry the
          # stylesheet got as a plain file has no digest of its own.
          digest = imported.dig(filepath, :digest) ||
                   Utils.css_module_digest(abs_path.presence || filepath)
          store(filepath, sideloaded, **, digest:)

          transformed_path = ''
          # Mirrors ConfigT#ShouldMinify - the suffix exists whenever identifiers are not
          # minified, and a class name the stylesheet does not define is worse than a long one.
          if Proscenium.config.debug || !Rails.env.production?
            # Keyed and built from the file's path under the app, or from the URL when there is
            # no file: `Pathname.new('').relative_path_from(Rails.root)` raises.
            identity = abs_path.presence || filepath
            transformed_path = SUFFIXES.compute_if_absent(identity) do
              relative = if abs_path.present?
                           Utils.css_module_relative_path(abs_path)
                         else
                           identity
                         end

              "_#{Utils.css_module_suffix(relative)}"
            end
          end

          "#{digest}#{transformed_path}"
        else
          Array(Resolver.resolve(filepath)).each { |fp| store(fp, sideloaded, **) }
        end
      end

      # Sideloads JS and CSS assets for the given Ruby filepath.
      #
      # Any files with the same base name and matching a supported extension will be sideloaded.
      # Only one JS and one CSS file will be sideloaded, with the first match used in the following
      # order:
      #  - JS extensions: .tsx, .ts, .jsx, and .js.
      #  - CSS extensions: .css.module, and .css.
      #
      # Example:
      #  - `app/views/layouts/application.rb`
      #  - `app/views/layouts/application.css`
      #  - `app/views/layouts/application.js`
      #  - `app/views/layouts/application.tsx`
      #
      # A request to sideload `app/views/layouts/application.rb` will result in `application.css`
      # and `application.tsx` being sideloaded. `application.js` will not be sideloaded because the
      # `.tsx` extension is matched first.
      #
      # @param filepath [Pathname] Absolute file system path of the Ruby file to sideload.
      # @param options [Hash] Options to pass to `import`.
      def sideload(filepath, **options)
        return if !Proscenium.config.side_load || (options[:js] == false && options[:css] == false)

        sideload_js(filepath, **options) unless options[:js] == false
        sideload_css(filepath, **options) unless options[:css] == false
      end

      def sideload_js(filepath, **)
        _sideload(filepath, JS_EXTENSIONS, **)
      end

      def sideload_css(filepath, **)
        _sideload(filepath, ['.css'], **)
      end

      def sideload_css_module(filepath, **)
        _sideload(filepath, ['.module.css'], **)
      end

      # @param filepath [Pathname] Absolute file system path of the Ruby file to sideload.
      # @param extensions [Array<String>] Supported file extensions to sideload.
      # @raise [ArgumentError] if `filepath` is not an absolute file system path.
      private def _sideload(filepath, extensions, **) # rubocop:disable Style/AccessModifierDeclarations
        return unless Proscenium.config.side_load

        if !filepath.is_a?(Pathname) || !filepath.absolute?
          raise ArgumentError, "`filepath` (#{filepath}) must be a `Pathname`, and an absolute path"
        end

        # Ensures extensions with more than one dot are handled correctly.
        filepath = filepath.sub_ext('').sub_ext('')

        extensions.find do |x|
          next unless (fp = filepath.sub_ext(x)).exist?

          import(fp.to_s, sideloaded: filepath, **)
        end
      end

      def each_stylesheet(delete: false)
        return if imported.blank?

        blk = proc do |key, options|
          if key.end_with?(*CSS_EXTENSIONS)
            yield(key, options)
            true
          end
        end

        delete ? imported.delete_if(&blk) : imported.each(&blk)
      end

      def each_javascript(delete: false)
        return if imported.blank?

        blk = proc do |key, options|
          if key.end_with?(*JS_EXTENSIONS)
            yield(key, options)
            true
          end
        end
        delete ? imported.delete_if(&blk) : imported.each(&blk)
      end

      def css_imported?
        imported&.keys&.any? { |x| x.end_with?(*CSS_EXTENSIONS) }
      end

      def js_imported?
        imported&.keys&.any? { |x| x.end_with?(*JS_EXTENSIONS) }
      end

      def imported?(filepath = nil)
        filepath ? imported&.key?(filepath) : !imported.blank?
      end

      private

      # Keyed by the resolved path, never the path given: a sideload passes an absolute file
      # system path. A repeat import merges its options in, later ones winning key by key, and does
      # not notify again; proscenium-ui's Select sideloads itself `lazy: true` over an eager
      # sideload of the same file.
      def store(key, sideloaded, **options)
        if (existing = imported[key])
          existing.merge!(options)
        elsif sideloaded
          ActiveSupport::Notifications.instrument 'sideload.proscenium', identifier: key,
                                                                         sideloaded: do
            imported[key] = options
          end
        else
          imported[key] = options
        end
      end
    end
  end
end
