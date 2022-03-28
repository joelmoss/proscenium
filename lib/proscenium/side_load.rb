# frozen_string_literal: true

module Proscenium
  module SideLoad
    DEFAULT_EXTENSIONS = %i[js css].freeze
    SUPPORTED_EXTENSIONS = %i[js css cssm].freeze
    MAPPED_EXTENSIONS = { cssm: :css }.freeze

    module_function

    # Side load the given asset `path`, by appending it to `Proscenium::Current.loaded`, which is a
    # Set of 'js' and 'css' asset paths. This is safe to call multiple times, as it uses Set's.
    # Meaning that side loading will never include duplicates.
    def append(path, *extensions)
      Proscenium::Current.loaded ||= SUPPORTED_EXTENSIONS.to_h { |e| [e, Set[]] }

      unless (unknown_extensions = extensions.difference(SUPPORTED_EXTENSIONS)).empty?
        raise ArgumentError, "unsupported extension(s): #{unknown_extensions.join(',')}"
      end

      loaded_types = []
      pathname = Rails.root.join(path)

      (extensions.empty? ? DEFAULT_EXTENSIONS : extensions).each do |ext|
        ext = ext.to_sym
        file_ext = MAPPED_EXTENSIONS.fetch(ext, ext)
        path_with_ext = "#{path}.#{file_ext}"

        next if Proscenium::Current.loaded[ext].include?(path_with_ext)
        next unless pathname.sub_ext(".#{file_ext}").exist?

        Proscenium::Current.loaded[ext] << path_with_ext
        loaded_types << ext
      end

      !loaded_types.empty? && Rails.logger.debug do
        "[Proscenium] Side loaded /#{path}.(#{loaded_types.join(',')})"
      end
    end

    module Monkey
      module TemplateRenderer
        private

        def render_template(view, template, layout_name, locals)
          if template.respond_to?(:type) && template.type == :html
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
