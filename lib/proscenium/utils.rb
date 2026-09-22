# frozen_string_literal: true

module Proscenium
  module Utils
    module_function

    # A filesystem path in the slash form everything it is matched against - Rails.root, the public
    # path, a gem's full_gem_path - already uses. Paths produced outside Ruby arrive in the form
    # the platform produced: esbuild's metafile, and every path Bun hands the test harness. On
    # Windows that is backslashes, so a plain `start_with?`/`delete_prefix` against Rails.root
    # misses, and nothing raises - the path just falls through to whatever handles "not ours".
    #
    # Windows only, because a backslash is a legal character in a file name everywhere else.
    #
    # @param path [String] an absolute filesystem path.
    # @return [String]
    def fs_path(path)
      Gem.win_platform? ? path.tr('\\', '/') : path
    end

    # Returns a short digest for the given `value`, intended for CSS module class name suffixes.
    #
    # @param value [#to_s] The value to create the digest from. This will usually be the absolute
    #   file system file path.
    # @return [String] digest of the given value.
    def css_module_digest(value)
      Digest::SHA1.hexdigest(value.to_s)[..7]
    end

    # The path a CSS module's class-name suffix is built from: the file's path under the app root.
    #
    # Where there is no such path - a gem on another drive than the app, which is RubyInstaller's
    # default - it is the absolute path itself. relative_path_from raised there, and failed every
    # view using the module. The absolute path is what esbuild falls back to when it builds the
    # stylesheet's class names (MakePrettyPaths keeps the path it could not relativise), and
    # internal/plugin/css.go does the same, so all three agree.
    #
    # @param abs_path [String] absolute file system path of the CSS module.
    # @return [Pathname, String]
    def css_module_relative_path(abs_path)
      Pathname.new(abs_path).relative_path_from(Rails.root)
    rescue ArgumentError
      abs_path
    end

    # Returns the readable part of a CSS module class name: the given path, made safe to use in a
    # class name.
    #
    # This is a port of `CssLocalAppendice` in esbuild-internal, which builds the class names in the
    # stylesheet. The two must agree byte for byte or the style silently does not apply, so change
    # them together (test/css_module_suffixes.json is checked against both). The rules: drop the
    # file extension, turn `/`, `\` and `.` into `-`, turn any other character outside
    # `A-Z a-z 0-9 - _` into `_`, and start with `_` if the result would start with a digit.
    #
    # Go works in runes, so the path is read as UTF-8 whatever its tag: the FFI hands paths back as
    # ASCII-8BIT, where each byte of a multibyte character would become a `_` of its own. A byte
    # that is not valid UTF-8 becomes one `_`, as it does in Go.
    #
    # @param path [#to_s] path of the CSS module file, relative to the app root.
    # @return [String]
    def css_module_suffix(path)
      path.to_s
          .dup.force_encoding(Encoding::UTF_8)
          .scrub { |bytes| '_' * bytes.bytesize }
          .sub(%r{\.[^./]*\z}, '')
          .gsub(%r{[/\\.]}, '-')
          .gsub(/[^A-Za-z0-9_-]/, '_')
          .sub(/\A(?=\d)/, '_')
    end

    # Merges the given array of attribute `name`'s into the `kw_arguments`. A bang attribute is one
    # that ends with an exclamation mark or - in Ruby parlance - a "bang", and has a boolean value.
    # Modifies the given `kw_attributes`, and only attribute names in `allowed` will be merged.
    #
    # @param names [Array(Symbol)] of argument names
    # @param kw_attributes [Hash] attributes to be merged with
    # @param allowed [Array(Symbol)] attribute names allowed to be merged as bang attributes
    #
    # Example:
    #
    #   def tab(name, *args, href:, **attributes)
    #     Hue::Utils.merge_bang_attributes!(args, attributes, [:current])
    #   end
    #
    # Allowing you to use either of the following API's:
    #
    #   tab 'Tab 1', required: true
    #   tab 'Tab 1', :required!
    #
    def merge_bang_attributes!(names, kw_attributes, allowed)
      allowed.each do |name|
        sym_name = name.to_sym
        bang_name = :"#{sym_name}!"

        next unless names.include?(bang_name)

        names.delete(bang_name)

        # Keyword arguments should override the bang.
        kw_attributes[sym_name] = true unless kw_attributes.key?(sym_name)
      end
    end
  end
end
