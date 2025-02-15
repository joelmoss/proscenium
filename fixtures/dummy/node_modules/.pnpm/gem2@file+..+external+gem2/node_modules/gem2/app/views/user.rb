module Gem2::Views
  class User < Proscenium::Phlex
    def view_template
      h1 { 'Hello' }
    end
  end
end
