# frozen_string_literal: true

module Fixtures
  module_function

  def path(*path)
    File.expand_path(File.join(__dir__, *path))
  end

  def app_path(*path)
    File.expand_path(File.join(__dir__, '../test/dummy', *path))
  end
end
