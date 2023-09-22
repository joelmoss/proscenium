module Gem3
  class Engine < ::Rails::Engine
    # isolate_namespace Gem3
    engine_name 'gem3'

    config.proscenium.engines << self

    initializer 'gem3.autoload' do
      # ActiveSupport::Dependencies.autoload_paths << "#{root}/app"

      # Rails.autoloaders.main.push_dir(root.join('app'), namespace: Gem3)

      ActiveSupport::Dependencies.autoload_paths.delete("#{root}/app/components")
      Rails.autoloaders.main.push_dir("#{root}/app/components", namespace: Gem3::Components)
    end
  end
end
