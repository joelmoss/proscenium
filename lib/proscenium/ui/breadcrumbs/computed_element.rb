# frozen_string_literal: true

module Proscenium::UI::Breadcrumbs
  class ComputedElement
    def initialize(element, context)
      @element = element
      @context = context
    end

    # If name is a Symbol of a controller method, that method is called.
    # If name is a Symbol of a controller instance variable, that variable is returned.
    # If name is a Proc, it is executed in the context of the controller instance.
    #
    # @return [String] the content of the breadcrumb element.
    def name
      @name ||= case name = @element.name
                when Symbol
                  if name.to_s.starts_with?('@')
                    name = get_instance_variable(name)
                    name.respond_to?(:for_breadcrumb) ? name.for_breadcrumb : name.to_s
                  else
                    res = @context.controller.send(name)
                    res.try(:for_breadcrumb) || res.to_s
                  end
                when Proc
                  @context.controller.instance_exec(&name)
                else
                  name.respond_to?(:for_breadcrumb) ? name.for_breadcrumb : name.to_s
                end
    end

    # If path is a Symbol of a controller method, that method is called.
    # If path is a Symbol of a controller instance variable, that variable is returned.
    # If path is an Array, each element is processed as above.
    # If path is a Proc, it is executed in the context of the controller instance.
    #
    # No matter what, the result is always passed to `url_for` before being returned.
    #
    # @return [String] the URL for the element
    def path # rubocop:disable Metrics/AbcSize
      @path ||= unless @element.path.nil?
                  case path = @element.path
                  when Array
                    path.map! { |x| x.to_s.starts_with?('@') ? get_instance_variable(x) : x }
                  when Symbol
                    if path.to_s.starts_with?('@')
                      path = get_instance_variable(path)
                    elsif @context.controller.respond_to?(path, true)
                      path = @context.controller.send(path)
                    end
                  when Proc
                    path = @context.controller.instance_exec(&path)
                  end

                  @context.url_for path
                end
    end

    private

    def get_instance_variable(element)
      unless @context.instance_variable_defined?(element)
        raise NameError, "undefined instance variable `#{element}' for breadcrumb", caller
      end

      @context.instance_variable_get element
    end
  end
end
