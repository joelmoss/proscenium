# frozen_string_literal: true

require 'active_support/current_attributes'

module Proscenium
  class Importer < ActiveSupport::CurrentAttributes
    JS_EXTENSIONS = %w[.tsx .ts .jsx .js].freeze
    CSS_EXTENSIONS = %w[.module.css .css].freeze

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
      # @param filepath [String] Absolute URL path (relative to Rails root) of the file to import.
      #   Should be the actual asset file, eg. app.css, some/component.js.
      # @param resolve [String] description of the file to resolve and import.
      # @return [String] the digest of the imported file path if a css module (*.module.css).
      def import(filepath = nil, resolve: nil, **)
        self.imported ||= {}

        filepath = Resolver.resolve(resolve) if !filepath && resolve
        css_module = filepath.end_with?('.module.css')

        unless self.imported.key?(filepath)
          # ActiveSupport::Notifications.instrument('sideload.proscenium', identifier: value)

          self.imported[filepath] = { ** }
          self.imported[filepath][:digest] = Utils.digest(filepath) if css_module
        end

        css_module ? self.imported[filepath][:digest] : nil
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
        _sideload(filepath, CSS_EXTENSIONS, **)
      end

      # @param filepath [Pathname] Absolute file system path of the Ruby file to sideload.
      # @param extensions [Array<String>] Supported file extensions to sideload.
      # @param options [Hash] Options to pass to `import`.
      # @raise [ArgumentError] if `filepath` is not an absolute file system path.
      private def _sideload(filepath, extensions, **options) # rubocop:disable Style/AccessModifierDeclarations
        return unless Proscenium.config.side_load

        if !filepath.is_a?(Pathname) || !filepath.absolute?
          raise ArgumentError, "`filepath` (#{filepath}) must be an absolute file system path"
        end

        filepath = filepath.sub_ext('')

        extensions.find do |x|
          if (fp = filepath.sub_ext(x)).exist?
            import(Resolver.resolve(fp.to_s), sideloaded: true, **options)
          end
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
    end
  end
end
