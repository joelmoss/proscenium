# frozen_string_literal: true

class ApplicationComponent < Proscenium::Phlex
  extend Literal::Attributes
  include Phlex::Rails::Helpers::Routes
  include Phlexible::Rails::AElement

  if Rails.env.development?
    def before_template
      comment { "Before #{self.class.name}" }
      super
    end
  end
end
