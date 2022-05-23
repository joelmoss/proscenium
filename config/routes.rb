Proscenium::Railtie.routes.draw do
  if Proscenium.config.auto_refresh
    mount Proscenium::Railtie.websocket => Proscenium.config.cable_mount_path
  end
end
