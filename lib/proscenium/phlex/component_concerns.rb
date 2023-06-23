# frozen_string_literal: true

module Proscenium::Phlex::ComponentConcerns
  module CssModules
    extend ActiveSupport::Concern
    include Proscenium::CssModule
    include Proscenium::Phlex::ResolveCssModules
  end
end
