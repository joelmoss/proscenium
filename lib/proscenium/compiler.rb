# frozen_string_literal: true

require 'open3'

module Proscenium
  class Compiler
    def self.build
      new.build
    end

    # Scans all paths for assets, and groups each by its builder. Each group is then compiled.
    def build
      cmd = "#{cli} #{Rails.root} #{Rails.application.config.proscenium.paths.join ' '}"

      stdout, stderr, status = Open3.capture3(cmd)

      raise stderr unless status.success?
      raise "Proscenium compiliation failed -- #{stderr}" unless stderr.empty?

      stdout
    end

    private

    def cli
      if ENV['PROSCENIUM_TEST']
        'deno run -q --import-map import_map.json -A lib/proscenium/compiler.js'
      else
        Rails.root.join('bin/compiler')
      end
    end
  end
end
