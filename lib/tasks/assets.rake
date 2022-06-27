# frozen_string_literal: true

namespace :assets do
  desc 'Compile all your assets'
  task precompile: :environment do
    Proscenium::Compiler.call
  end
end
