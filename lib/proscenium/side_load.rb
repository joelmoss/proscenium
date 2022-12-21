# frozen_string_literal: true

module Proscenium
  class SideLoad
    EXTENSIONS = %i[js css].freeze
    EXTENSION_MAP = { '.css' => :css, '.js' => :js }.freeze

    attr_reader :path

    # Side load the given asset `path`, by appending it to `Proscenium::Current.loaded`, which is a
    # Set of 'js' and 'css' asset paths. This is idempotent, so side loading will never include
    # duplicates.
    def self.append(path, extension_map = EXTENSION_MAP)
      new(path, extension_map)
    end

    # @param path [Pathname, String] The path of the file to be side loaded.
    # @param extensions [Array] File extensions to side load (default: DEFAULT_EXTENSIONS)
    def initialize(path, extension_map)
      @path = (path.is_a?(Pathname) ? path : Rails.root.join(path)).sub_ext('')
      @extension_map = extension_map

      Proscenium::Current.loaded ||= EXTENSIONS.to_h { |e| [e, Set.new] }

      append_to_loaded
    end

    private

    def append_to_loaded
      root, relative_path, path_to_load = Proscenium::Utils.path_pieces(path)

      @extension_map.each do |ext, type|
        path_with_ext = "#{relative_path}#{ext}"

        # Make sure path is not already side loaded, and actually exists.
        next if Proscenium::Current.loaded[type].include?(path_with_ext)
        next unless (full_path = Pathname.new(root).join(path_with_ext)).exist?

        digest = Proscenium::Utils.digest(full_path)
        Proscenium::Current.loaded[type] << [digest, log("#{path_to_load}#{ext}")]
      end
    end

    def log(value)
      Proscenium.logger.debug "Side loaded #{value}"
      value
    end

    # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    module Monkey
      module TemplateRenderer
        private

        def render_template(view, template, layout_name, locals)
          layout = find_layout(layout_name, locals.keys, [formats.first])
          renderable = template.instance_variable_get(:@renderable)

          if Object.const_defined?(:ViewComponent) &&
             template.is_a?(ActionView::Template::Renderable) &&
             renderable.class < ::ViewComponent::Base && renderable.class.format == :html
            # Side load controller rendered ViewComponent
            Proscenium::SideLoad.append "app/views/#{layout.virtual_path}" if layout
            Proscenium::SideLoad.append "app/views/#{renderable.virtual_path}"
          elsif template.respond_to?(:virtual_path) &&
                template.respond_to?(:type) && template.type == :html
            # Side load regular view template.
            Proscenium::SideLoad.append "app/views/#{layout.virtual_path}" if layout

            # Try side loading the variant template
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
    # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
  end
end
