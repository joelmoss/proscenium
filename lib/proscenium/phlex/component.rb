# frozen_string_literal: true

class Proscenium::Phlex::Component < Proscenium::Phlex
  private

  def virtual_path
    "/#{self.class.name.underscore}"
  end
end
