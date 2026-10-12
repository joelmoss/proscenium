# frozen_string_literal: true

module Proscenium
  # The model of gem dependency contexts (#154), which the engine and the `proscenium` CLI share.
  # Its files load nothing of either: not ActiveSupport, and nothing under cli/. The CLI requires
  # each file it needs; the engine reaches them through these autoloads.
  module Contexts
    autoload :Map, "#{__dir__}/contexts/map"
    autoload :MappingGeneration, "#{__dir__}/contexts/mapping_generation"
    autoload :Messages, "#{__dir__}/contexts/messages"
    autoload :Plan, "#{__dir__}/contexts/plan"
    autoload :Projection, "#{__dir__}/contexts/projection"
    autoload :Rules, "#{__dir__}/contexts/rules"
    autoload :Stale, "#{__dir__}/contexts/stale"
  end
end
