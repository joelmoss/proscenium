# frozen_string_literal: true

namespace :assets do
  desc 'Compile Proscenium assets'
  task precompile: :environment do
    puts "\nPre-compiling assets..."

    raise 'Assets pre-compilation failed!' unless Proscenium::Builder.compile

    puts "\nAssets pre-compiled successfully."

    if Rails.env.development?
      puts "\nWarning: You are precompiling assets in development. Rails will not " \
           'serve any changed assets until you delete ' \
           "public#{Rails.application.config.proscenium.output_dir}/.manifest.json"
    end
  end
end
