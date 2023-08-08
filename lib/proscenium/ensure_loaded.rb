# frozen_string_literal: true

module Proscenium
  module EnsureLoaded
    def self.included(child)
      child.class_eval do
        append_after_action do
          if request.format.html? && Importer.imported?
            if Importer.js_imported?
              raise NotIncludedError, 'There are javascripts to be included, but they have ' \
                                      'not been included. Did you forget to add the ' \
                                      '`#include_javascripts` helper in your views?'
            end

            if Importer.css_imported?
              raise NotIncludedError, 'There are stylesheets to be included, but they have ' \
                                      'not been included. Did you forget to add the ' \
                                      '`#include_stylesheets` helper in your views?'
            end
          end
        end
      end
    end
  end
end
