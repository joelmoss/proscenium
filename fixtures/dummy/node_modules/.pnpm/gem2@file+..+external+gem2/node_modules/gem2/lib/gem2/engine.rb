module Gem2
  class Engine < ::Rails::Engine
    # isolate_namespace Gem2
    engine_name 'gem2'

    initializer 'gem2.autoload' do
      # ActiveSupport::Dependencies.autoload_paths << "#{root}/app"

      # Rails.autoloaders.main.push_dir(root.join('app'), namespace: Gem2)

      ActiveSupport::Dependencies.autoload_paths.delete("#{root}/app/components")
      Rails.autoloaders.main.push_dir("#{root}/app/components", namespace: Gem2::Components)
    end
  end
end
