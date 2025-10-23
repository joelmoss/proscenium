# frozen_string_literal: true

namespace :proscenium do
  desc 'Compile Proscenium assets'
  task compile: :environment do
    puts 'Compiling assets...'
    ap Proscenium::Builder.compile
    puts 'Assets compiled successfully.'
  end
end
