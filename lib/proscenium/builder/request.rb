# frozen_string_literal: true

require 'ffi'

module Proscenium
  class Builder
    module Request
      extend FFI::Library

      raise UnsupportedPlatform, LIBRARY_PATH unless LIBRARY_PATH.exist?

      ffi_lib LIBRARY_PATH.to_s

      # Windows unmaps the library at interpreter exit, and the Go runtime does not survive it.
      #
      # ffi's library_free calls dl_close on every platform but macOS, which is FreeLibrary here,
      # and Ruby runs every T_DATA free during VM teardown. Go's c-shared runtime cannot be
      # unloaded: its threads are still running when the mapping goes. On Linux this never bites,
      # because the Go linker marks the library nodelete and dlclose is a no-op; Windows has no
      # equivalent. Measured on windows-latest: three of five plain `require` runs exited 139,
      # while five of five exited 0 when the script ended in `exit!`, which skips the teardown.
      #
      # Pinning the module means the reference count never reaches zero, so FreeLibrary returns
      # without unmapping anything. Nothing here needs the handle, only the pin.
      if Gem.win_platform?
        module Kernel32
          extend FFI::Library

          ffi_lib 'kernel32'
          attach_function :GetModuleHandleExW, %i[uint32 buffer_in pointer], :int
        end

        # GET_MODULE_HANDLE_EX_FLAG_PIN. Backslashes, because GetModuleHandle documents that a full
        # path must use them, and LIBRARY_PATH is built from __dir__, which uses "/". Checked,
        # because a pin that quietly failed would bring back an exit crash that only happens some
        # of the time, with nothing to say why.
        name = "#{LIBRARY_PATH.to_s.tr('/', '\\')}\0".encode(Encoding::UTF_16LE)
        if Kernel32.GetModuleHandleExW(0x1, name, FFI::MemoryPointer.new(:pointer)).zero?
          warn "Proscenium could not pin #{LIBRARY_PATH} (Windows error " \
               "#{FFI::LastError.winapi_error}), so Ruby may crash when it exits."
        end
      end

      enum :environment, [:development, 1, :test, :production]

      # `blocking: true` releases the GVL for the duration of the call, so a build/resolve
      # doesn't stall unrelated Ruby threads (eg. other requests in a multi-threaded server).
      # Safe to do because the Go side shares nothing between calls: each call parses its own
      # config, and the caches that outlive a call (i18n, svg, npm replacements) carry their own
      # locks. See the note in main.go. There is no serialising mutex any more; a new piece of
      # global state on the Go side needs its own.

      attach_function :build_to_string, [
        :string, # Path or entry point.
        :pointer # Config as JSON.
      ], Result.by_value, blocking: true

      attach_function :resolve, [
        :string, # path or entry point
        :pointer # Config as JSON.
      ], ResolveResult.by_value, blocking: true

      attach_function :compile, [
        :pointer # Config as JSON.
      ], CompileResult.by_value, blocking: true

      attach_function :reset_config, [], :void, blocking: true

      attach_function :free_cstr, [:pointer], :void
    end
  end
end
