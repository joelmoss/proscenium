module Gem4
  class Engine < ::Rails::Engine
    # isolate_namespace Gem4
    engine_name 'gem4'

    config.proscenium.engines[:gem4] = root

    initializer 'gem4.autoload' do
      # ActiveSupport::Dependencies.autoload_paths << "#{root}/app"

      # Rails.autoloaders.main.push_dir(root.join('app'), namespace: Gem4)

      ActiveSupport::Dependencies.autoload_paths.delete("#{root}/app/components")
      Rails.autoloaders.main.push_dir("#{root}/app/components", namespace: Gem4::Components)
    end
  end
end
