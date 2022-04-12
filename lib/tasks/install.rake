namespace :proscenium do
  desc 'Install the Proscenium CLI'
  task install: :environment do
    from = Pathname.new(__dir__).join('../../exe/proscenium')
    to = Rails.root.join('bin/proscenium')
    FileUtils.rm to
    FileUtils.copy from, to

    puts 'Installed Proscenium CLI to `bin/proscenium`.'
  end
end
