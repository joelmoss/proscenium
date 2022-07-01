# frozen_string_literal: true

namespace :proscenium do
  desc 'Compile all your assets with Proscenium'
  task precompile: :environment do
    puts 'Precompiling assets with Proscenium...'
    Proscenium::Precompile.call
    puts 'Proscenium successfully precompiled your assets 🎉'
  end
end

if Rake::Task.task_defined?('assets:precompile')
  Rake::Task['assets:precompile'].enhance do
    Rake::Task['proscenium:precompile'].invoke
  end
else
  Rake::Task.define_task('assets:precompile' => ['proscenium:precompile'])
  Rake::Task.define_task('assets:clean') # null task just so Heroku builds don't fail
end
