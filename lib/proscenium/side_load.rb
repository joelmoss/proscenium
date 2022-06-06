# frozen_string_literal: true

module Proscenium
  module SideLoad
    DEFAULT_EXTENSIONS = %i[js css].freeze
    EXTENSIONS = %i[js css].freeze

    class NotFound < StandardError
      def initialize(pathname)
        @pathname = pathname
        super
      end

      def message
        "#{@pathname} does not exist"
      end
    end

    module_function

    # Side load the given asset `path`, by appending it to `Proscenium::Current.loaded`, which is a
    # Set of 'js' and 'css' asset paths. This is safe to call multiple times, as it uses Set's.
    # Meaning that side loading will never include duplicates.
    def append(path, *extensions)
      Proscenium::Current.loaded ||= EXTENSIONS.to_h { |e| [e, Set[]] }

      unless (unknown_extensions = extensions.difference(EXTENSIONS)).empty?
        raise ArgumentError, "unsupported extension(s): #{unknown_extensions.join(',')}"
      end

      loaded_types = []

      (extensions.empty? ? DEFAULT_EXTENSIONS : extensions).each do |ext|
        path_with_ext = "#{path}.#{ext}"
        ext = ext.to_sym

        next if Proscenium::Current.loaded[ext].include?(path_with_ext)
        next unless Rails.root.join(path_with_ext).exist?

        Proscenium::Current.loaded[ext] << path_with_ext
        loaded_types << ext
      end

      !loaded_types.empty? && Rails.logger.debug do
        "[Proscenium] Side loaded /#{path}.(#{loaded_types.join(',')})"
      end
    end

    # Like #append, but only accepts a single `path` argument, which must be a Pathname. Raises
    # `NotFound` if path does not exist,
    def append!(pathname)
      Proscenium::Current.loaded ||= EXTENSIONS.to_h { |e| [e, Set[]] }

      unless pathname.is_a?(Pathname)
        raise ArgumentError, "Argument `pathname` (#{pathname}) must be a Pathname"
      end

      ext = pathname.extname.sub('.', '').to_sym
      path = pathname.relative_path_from(Rails.root)

      raise ArgumentError, "unsupported extension: #{ext}" unless EXTENSIONS.include?(ext)

      return if Proscenium::Current.loaded[ext].include?(path)

      raise NotFound, path unless pathname.exist?

      Proscenium::Current.loaded[ext] << path

      Rails.logger.debug "[Proscenium] Side loaded /#{path}"
    end

    module Monkey
      module TemplateRenderer
        private

        def render_template(view, template, layout_name, locals)
          if template.respond_to?(:virtual_path) &&
             template.respond_to?(:type) && template.type == :html
            if (layout = layout_name && find_layout(layout_name, locals.keys, [formats.first]))
              Proscenium::SideLoad.append "app/views/#{layout.virtual_path}" # layout
            end

            if template.respond_to?(:variant) && template.variant
              Proscenium::SideLoad.append "app/views/#{template.virtual_path}+#{template.variant}"
            end

            # The variant template may not exist (above), so we try the regular non-variant path.
            Proscenium::SideLoad.append "app/views/#{template.virtual_path}"
          end

          super
        end
      end
    end
  end
end
