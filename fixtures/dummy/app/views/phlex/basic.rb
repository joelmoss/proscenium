class Views::Phlex::Basic < Proscenium::Phlex
  def template
    super do
      h1 { 'Hello' }
    end
  end
end
