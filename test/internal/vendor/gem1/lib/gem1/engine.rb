module Gem1
  class Engine < ::Rails::Engine
    # isolate_namespace Gem1

    # Append the gem root
    config.proscenium.include_ruby_gems['gem1'] = root

    initializer 'gem1.autoload' do
      Rails.autoloaders.main.push_dir(root.join('app'), namespace: Gem1)
    end
  end
end
