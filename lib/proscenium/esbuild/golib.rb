require 'ffi'

module Proscenium
  module Esbuild::Golib
    extend FFI::Library
    ffi_lib "#{__dir__}/main.so"
    attach_function :transform, [:string], :string
    attach_function :build, [:string], :string
  end
end
