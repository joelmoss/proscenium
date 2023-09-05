# frozen_string_literal: true

module Proscenium
  module Phlex::CssModules
    include Proscenium::CssModule

    def self.included(base)
      base.extend CssModule::Path
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
    # For example, the following will side load the CSS module file at /lib/users.module.css, and
    # add the CSS Module name `name` to the <div>.
    #
    #   class User::Component < Proscenium::Phlex
    #     def template
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
        attributes[:class] = cssm.class_names(*names)
      end

      attributes
    end
  end
end
