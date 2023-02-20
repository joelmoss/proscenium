# frozen_string_literal: true

require 'open3'

module Proscenium
  class Precompile
    def self.call
      new.call
    end

    def call
      Rails.application.config.proscenium.glob_types.find do |type, globs|
        cmd = "#{cli type} --root #{Rails.root} '#{globs.join "' '"}' --write"
        _, stderr, status = Open3.capture3(cmd)

        raise stderr unless status.success?
        raise "#{type} compiliation failed -- #{stderr}" unless stderr.empty?
      end
    end

    private

    def cli(type)
      if ENV['PROSCENIUM_TEST']
        "deno run -q -A lib/proscenium/compilers/#{type}.js"
      else
        Gem.bin_path 'proscenium', type.to_s
      end
    end
  end
end
