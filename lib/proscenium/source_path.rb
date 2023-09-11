# frozen_string_literal: true

# Include this into any class to expose a `source_path` class and instance method, which will return
# the absolute file system path to the current object.
module Proscenium::SourcePath
  def self.included(base)
    base.extend ClassMethods
  end

  module ClassMethods
    def source_path
      @source_path ||= name.nil? ? nil : Pathname.new(const_source_location(name).first)
    end
  end
end
