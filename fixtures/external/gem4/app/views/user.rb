module Gem4::Views
  class User < Proscenium::Phlex
    def template
      h1 { 'Hello' }
    end
  end
end
