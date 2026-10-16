---
name: ffi-reviewer
description: Reviews a change to the Ruby-Go FFI boundary (lib/proscenium/builder/request.rb, lib/proscenium/builder.rb, main.go) for struct, signature and memory mismatches.
---

# FFI Bridge Reviewer

Review changes to the Ruby-Go FFI boundary for correctness.

## When to use

When changes touch `lib/proscenium/builder/request.rb`, `lib/proscenium/builder.rb`, or `main.go`.

## Files to review

- `lib/proscenium/builder/request.rb` — `ffi_lib` and the `attach_function` declarations
- `lib/proscenium/builder.rb` — the result structs, and the calls that read and free them
- `main.go` — C struct definitions (in the comment block) and the exported Go functions

## What to check

1. **Struct field alignment**: Ruby `FFI::Struct` layouts must match the C struct definitions in `main.go`:
   - `Result`: `success` (bool/int), `response` (pointer/char*), `content_hash` (pointer/char*)
   - `ResolveResult`: `success` (bool/int), `url_path` (pointer/char*), `abs_path` (pointer/char*)
   - `CompileResult`: `success` (bool/int), `messages` (pointer/char*)
2. **Function signatures**: `attach_function` declarations must match `//export` Go functions:
   - `build_to_string(string, pointer) -> Result`
   - `resolve(string, pointer) -> ResolveResult`
   - `compile(pointer) -> CompileResult`
   - `reset_config() -> void`
   - `free_cstr(pointer) -> void`
3. **Parameter order and types**: Ensure Ruby FFI types (`:string`, `:pointer`, `:bool`, `:void`) correspond to Go C types (`*C.char`, `C.int`)
4. **Return value handling**: every string field is read through `read_and_free` in builder.rb, never as `:string`
5. **Memory management**: `FFI::MemoryPointer.from_string` for config JSON; each `C.CString` Go returns is freed exactly once by `free_cstr`, since the Go runtime cannot collect it
6. **New functions**: Any new `//export` function in Go must have a corresponding `attach_function` in `Request`, and vice versa. Keep every reference to the library inside `Request`, never in builder.rb's class body (see the Puma fork gotcha in AGENTS.md)
