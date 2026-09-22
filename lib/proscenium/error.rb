# frozen_string_literal: true

module Proscenium
  # The base of every error Proscenium raises.
  #
  # In a file of its own so that lib/proscenium/builder.rb can load without the rest of the gem:
  # the release workflow loads the compiled library from an installed gem to prove it works, with
  # no Rails app and no Rails, and builder.rb subclasses this at class-definition time.
  class Error < StandardError; end
end
