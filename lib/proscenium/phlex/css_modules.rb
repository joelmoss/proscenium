# frozen_string_literal: true

module Proscenium
  module Phlex::CssModules
    include Proscenium::CssModule

    def self.included(base)
      base.extend CssModule::Path
      base.extend ClassMethods
    end

    module ClassMethods
      # Set of CSS module paths that have been resolved after being transformed from 'class' HTML
      # attributes. See #process_attributes. This is here because Phlex caches attributes. Which
      # means while the CSS class names will be transformed, any resolved paths will be lost in
      # subsequent requests.
      attr_accessor :resolved_css_module_paths
    end

    def before_template
      self.class.resolved_css_module_paths ||= Concurrent::Set.new
      super
    end

    def after_template
      self.class.resolved_css_module_paths.each do |path|
        Proscenium::Importer.import path, sideloaded: true
      end

      super
    end

    # Resolve and side load any CSS modules in the "class" attributes, where a CSS module is a class
    # name beginning with a `@`. The class name is resolved to a CSS module name based on the file
    # system path of the Phlex class, and any CSS file is side loaded.
    #
    # For example, the following will side load the CSS module file at
    # app/components/user/component.module.css, and add the CSS Module name `user_name` to the
    # <div>.
    #
    #   # app/components/user/component.rb
    #   class User::Component < Proscenium::Phlex
    #     def view_template
    #       div class: :@user_name do
    #         'Joel Moss'
    #       end
    #     end
    #   end
    #
    # Additionally, any class name containing a `/` is resolved as a CSS module path. Allowing you
    # to use the same syntax as a CSS module, but without the need to manually import the CSS file.
    #
    # For example, the following will side load the CSS module file at /lib/users.module.css, and
    # add the CSS Module name `name` to the <div>.
    #
    #   class User::Component < Proscenium::Phlex
    #     def view_template
    #       div class: '/lib/users@name' do
    #         'Joel Moss'
    #       end
    #     end
    #   end
    #
    # @raise [Proscenium::CssModule::Resolver::NotFound] If a CSS module file is not found for the
    #   Phlex class file path.
    def process_attributes(**attributes)
      if attributes.key?(:class) && (attributes[:class] = tokens(attributes[:class])).include?('@')
        names = attributes[:class].is_a?(Array) ? attributes[:class] : attributes[:class].split

        attributes[:class] = cssm.class_names(*names).map do |name, path|
          self.class.resolved_css_module_paths << path if path
          name
        end
      end

      attributes
    end
  end
end
