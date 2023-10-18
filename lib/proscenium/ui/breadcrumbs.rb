# frozen_string_literal: true

module Proscenium::UI
  # Provides breadcrumb functionality for controllers and views. Breadcrumbs are a type of
  # navigation that show the user where they are in the application's hierarchy.
  # The `Proscenium::UI::Breadcrumbs::Control` module provides the `add_breadcrumb` and
  # `prepend_breadcrumb` class methods for adding breadcrumb elements, and is intended to be
  # included in your controllers.
  #
  # The `add_breadcrumb` method adds a new breadcrumb element to the end of the collection, while
  # the `prepend_breadcrumb` method adds a new breadcrumb element to the beginning of the
  # collection. Both methods take a name, and path as arguments. The name argument is the name or
  # content of the breadcrumb, while the path argument is the path (route) to use as the HREF for
  # the breadcrumb.
  #
  #   class UsersController < ApplicationController
  #     include Proscenium::UI::Breadcrumbs::Control
  #     add_breadcrumb 'Users', :users_path
  #   end
  #
  # Display the breadcrumbs in your views with the breadcrumbs component.
  # @see `Proscenium::UI::Breadcrumbs::Component`.
  #
  # At it's simplest, you can add a breadcrumb with a name of "User", and a path of "/users" like
  # this:
  #
  #   add_breadcrumb 'Foo', '/foo'
  #
  # The value of the path is always passed to `url_for` before being rendered. It is also optional,
  # and if omitted, the breadcrumb will be rendered as plain text.
  #
  # Both name and path can be given a Symbol, which can be used to call a method of the same name on
  # the controller. If a Symbol is given as the path, and no method of the same name exists, then
  # `url_for` will be called with the Symbol as the argument. Likewise, if an Array is given as the
  # path, then `url_for` will be called with the Array as the argument.
  #
  # If a Symbol is given as the path or name, and it begins with `@` (eg. `:@foo`), then the
  # instance variable of the same name will be called.
  #
  #   add_breadcrumb :@foo, :@bar
  #
  # A Proc can also be given as the name and/or path. The Proc will be called within the context of
  # the controller.
  #
  #   add_breadcrumb -> { @foo }, -> { @bar }
  #
  # Passing an object that responds to `#for_breadcrumb` as the name will call that method on the
  # object to get the breadcrumb name.
  #
  module Breadcrumbs
    extend ActiveSupport::Autoload

    autoload :Control
    autoload :ComputedElement
    autoload :Component

    # Represents a navigation element in the breadcrumb collection.
    class Element
      attr_accessor :name, :path, :options

      # @param  name [String] the element/link name
      # @param  path [String] the element/link URL
      # @param  options [Hash] the element/link options
      # @return [Element]
      def initialize(name, path = nil, options = {})
        self.name = name
        self.path = path
        self.options = options
      end
    end
  end
end
