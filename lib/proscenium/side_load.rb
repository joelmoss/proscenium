# frozen_string_literal: true

module Proscenium
  module SideLoad
    module_function

    # Side load the given asset `path`, by appending the mapped Webpack entry points to
    # `Proscenium::Current.loaded`, which is a Set of 'js' and 'css' asset paths. This is safe to
    # call multiple times, as it uses Set's. Meaning that side loading will never include
    # duplicates.
    def append(path)
      Proscenium::Current.loaded ||= { entries: Set[], js: Set[], css: Set[] }

      return if Proscenium::Current.loaded[:entries].include?(path)

      loaded_types = []
      pathname = Rails.root.join(path)

      %i[js css].each do |ext|
        next unless pathname.sub_ext(".#{ext}").exist?
        next if Proscenium::Current.loaded[ext].include?(path)

        Proscenium::Current.loaded[ext] << "#{path}.#{ext}"
        loaded_types << ext
      end

      # Track the path so we don't attempt a manifest lookup and load again. We do this even if no
      # assets are found in the manifest, as that simply means there is nothing to load. In which
      # case there is no need to do it again.
      Proscenium::Current.loaded[:entries] << path

      !loaded_types.empty? && Rails.logger.debug do
        "[Proscenium] Side loaded #{path} (#{loaded_types.join(',')})"
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
