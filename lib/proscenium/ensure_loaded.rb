# frozen_string_literal: true

module Proscenium
  NotIncludedError = Class.new(StandardError)

  module EnsureLoaded
    def self.included(child)
      child.class_eval do
        append_after_action do
          if request.format.html? && !response.redirect? && Importer.imported?
            msg = <<-TEXT.squish
              There are side loaded and imported assets to be included, but they have not been
              included in the page. Did you forget to add the `#include_assets` helper in your
              views? These assets were imported but not included:
              #{Importer.imported.keys.to_sentence}
            TEXT

            if Proscenium.config.ensure_loaded == :log
              Rails.logger.warn do
                "#{ActiveSupport::LogSubscriber.new.send(:color, '  [Proscenium]', nil,
                                                         bold: true)} #{msg}"
              end
            elsif Proscenium.config.ensure_loaded == :raise
              raise NotIncludedError, msg
            end
          end
        end
      end
    end
  end
end
