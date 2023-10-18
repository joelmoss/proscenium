# frozen_string_literal: true

module ViewHelper
  def self.extended(parent)
    parent.class_exec do
      delegate :view_context, to: :controller

      def controller
        @controller ||= ActionView::TestCase::TestController.new
      end
    end
  end

  def view(obj, &blk)
    let :instance do
      instance_exec(&obj)
    end

    let :view do
      result = if blk
                 instance.call(view_context: view_context) do
                   instance.instance_exec(instance, &blk)
                 end
               else
                 instance.call(view_context: view_context)
               end

      ::Capybara::Node::Simple.new result
    end
  end
end
