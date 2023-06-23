# frozen_string_literal: true

class Proscenium::SideLoad
  module EnsureLoaded
    def self.included(child)
      child.class_eval do
        append_after_action do
          if Proscenium::Current.loaded
            if Proscenium::Current.loaded[:js].present?
              raise NotIncludedError, 'There are javascripts to be side loaded, but they have ' \
                                      'not been included. Did you forget to add the ' \
                                      '`#side_load_javascripts` helper in your views?'
            end

            if Proscenium::Current.loaded[:css].present?
              raise NotIncludedError, 'There are stylesheets to be side loaded, but they have  ' \
                                      'notbeen included. Did you forget to add the ' \
                                      '`#side_load_stylesheets` helper in your views?'
            end
          end
        end
      end
    end
  end
end
