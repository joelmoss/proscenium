# frozen_string_literal: true

module Proscenium
  module Phlex::ResolveCssModules
    extend ActiveSupport::Concern

    class_methods do
      attr_accessor :side_load_cache
    end

    def before_template
      self.class.side_load_cache ||= Set.new
      super
    end

    # Resolve and side load any CSS modules in the "class" attributes, where a CSS module is a class
    # name beginning with a `@`. The class name is resolved to a CSS module name based on the file
    # system path of the Phlex class, and any CSS file is side loaded.
    #
    # For example, the following will side load the CSS module file at
    # app/components/user/component.module.css, and add the CSS Module name `user_name` to the <div>.
    #
    #   # app/components/user/component.rb
    #   class User::Component < Proscenium::Phlex
    #     def template
    #       div class: :@user_name do
    #         'Joel Moss'
    #       end
    #     end
    #   end
    #
    # Additionally, any class name containing a `/` is resolved as a CSS module path. Allowing you
    # to use the same syntax as a CSS module, but without the need to manually import the CSS file.
    #
    # For example, the following will side load the CSS module file at /lib/users.module.css, and add
    # the CSS Module name `name` to the <div>.
    #
    #   class User::Component < Proscenium::Phlex
    #     def template
    #       div class: '/lib/users@name' do
    #         'Joel Moss'
    #       end
    #     end
    #   end
    #
    # The given class name should be underscored, and the resulting CSS module name will be
    # `camelCased` with a lower case first character.
    #
    # @raise [Proscenium::CssModule::Resolver::NotFound] If a CSS module file is not found for the
    #   Phlex class file path.
    def process_attributes(**attributes)
      if attributes.key?(:class) && (attributes[:class] = tokens(attributes[:class])).include?('@')
        resolver = CssModule::ClassNamesResolver.new(attributes[:class], path)
        self.class.side_load_cache.merge resolver.stylesheets
        attributes[:class] = resolver.class_names
      end

      attributes
    end

    def after_template
      super
      self.class.side_load_cache&.each { |path| SideLoad.append! path, :css }
    end
  end
end
