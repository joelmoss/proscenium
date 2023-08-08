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
      # @param filepath [String] Absolute path (relative to Rails root) of the file to import.
      #   Should be the actual asset file, eg. app.css, some/component.js.
      # @return [String] the digest of the imported file path if a css module (*.module.css).
      def import(filepath, **options)
        self.imported ||= {}

        css_module = filepath.end_with?('.module.css')

        unless self.imported.key?(filepath)
          # ActiveSupport::Notifications.instrument('sideload.proscenium', identifier: value)

          self.imported[filepath] = { **options }
          self.imported[filepath][:digest] = Utils.digest(filepath) if css_module
        end

        css_module ? self.imported[filepath][:digest] : nil
      end

      # Sideloads JS and CSS assets for the given Ruby file.
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
      def sideload(filepath, **options)
        filepath = Rails.root.join(filepath) unless filepath.is_a?(Pathname)
        filepath = filepath.sub_ext('')

        import_if_exists = lambda do |x|
          if (fp = filepath.sub_ext(x)).exist?
            import(Resolver.resolve(fp.to_s), sideloaded: true, **options)
          end
        end

        JS_EXTENSIONS.find(&import_if_exists)
        CSS_EXTENSIONS.find(&import_if_exists)
      end

      def each_stylesheet(delete: false)
        return if imported.blank?

        blk = proc { |key, options| key.end_with?(*CSS_EXTENSIONS) && yield(key, options) }
        delete ? imported.delete_if(&blk) : imported.each(&blk)
      end

      def each_javascript(delete: false)
        return if imported.blank?

        blk = proc { |key, options| key.end_with?(*JS_EXTENSIONS) && yield(key, options) }
        delete ? imported.delete_if(&blk) : imported.each(&blk)
      end

      def css_imported?
        imported&.keys&.any? { |x| x.end_with?(*CSS_EXTENSIONS) }
      end

      def js_imported?
        imported&.keys&.any? { |x| x.end_with?(*JS_EXTENSIONS) }
      end

      def multiple_js_imported?
        imported&.keys&.many? { |x| x.end_with?(*JS_EXTENSIONS) }
      end

      def imported?(filepath = nil)
        filepath ? imported&.key?(filepath) : !imported.blank?
      end
    end
  end
end
