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
      # @return [String|nil] the digest of the imported file path if a css module (*.module.css).
      def import(filepath = nil, sideloaded: false, **)
        self.imported ||= {}

        filepath = "/node_modules/#{filepath}" if filepath.start_with?('@rubygems/')
        css_module = filepath.match?(/\.module(-\$[a-z0-9]+\$)?\.css$/i)

        unless self.imported.key?(filepath)
          if sideloaded
            ActiveSupport::Notifications.instrument 'sideload.proscenium', identifier: filepath,
                                                                           sideloaded: do
              self.imported[filepath] = { ** }
              self.imported[filepath][:digest] ||= Utils.digest(filepath) if css_module

              if self.imported[filepath][:digest].is_a?(Proc)
                self.imported[filepath][:digest] = self.imported[filepath][:digest].call
              end
            end
          else
            self.imported[filepath] = { ** }
            self.imported[filepath][:digest] ||= Utils.digest(filepath) if css_module

            if self.imported[filepath][:digest].is_a?(Proc)
              self.imported[filepath][:digest] = self.imported[filepath][:digest].call
            end
          end
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
        _sideload(filepath, ['.css'], **)
      end

      def sideload_css_module(filepath, **)
        _sideload(filepath, ['.module.css'], **)
      end

      # @param filepath [Pathname] Absolute file system path of the Ruby file to sideload.
      # @param extensions [Array<String>] Supported file extensions to sideload.
      # @param options [Hash] Options to pass to `import`.
      # @return [Array<String>] The imported file paths.
      # @raise [ArgumentError] if `filepath` is not an absolute file system path.
      private def _sideload(filepath, extensions, **options) # rubocop:disable Style/AccessModifierDeclarations
        return unless Proscenium.config.side_load

        if !filepath.is_a?(Pathname) || !filepath.absolute?
          raise ArgumentError, "`filepath` (#{filepath}) must be a `Pathname`, and an absolute path"
        end

        # Ensures extensions with more than one dot are handled correctly.
        filepath = filepath.sub_ext('').sub_ext('')

        sideloaded = []

        extensions.find do |x|
          if (fp = filepath.sub_ext(x)).exist?
            sideloaded << import(Resolver.resolve(fp.to_s), sideloaded: filepath, **options)
          end
        end

        sideloaded
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
