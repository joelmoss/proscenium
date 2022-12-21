class Views::Phlex::Basic < Proscenium::Phlex
  include Proscenium::Phlex::Page

  def template
    super do
      h1 { 'Hello' }
    end
  end
end
