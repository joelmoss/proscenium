# frozen_string_literal: true

namespace :proscenium do
  desc 'Install the Proscenium CLI'
  task install: :environment do
    from = Pathname.new(__dir__).join('../../exe/proscenium')
    to = Rails.root.join('bin/proscenium')
    FileUtils.rm to, force: true
    FileUtils.copy from, to

    puts 'Installed proscenium CLI to `bin/proscenium`.'

    from = Pathname.new(__dir__).join('../../exe/parcel_css')
    to = Rails.root.join('bin/parcel_css')
    FileUtils.rm to, force: true
    FileUtils.copy from, to

    puts 'Installed parcel_css CLI to `bin/parcel_css`.'
  end
end
