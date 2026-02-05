# FFI Bridge Reviewer

Review changes to the Ruby-Go FFI boundary for correctness.

## When to use

When changes touch `lib/proscenium/builder.rb`, `lib/proscenium/resolver.rb`, or `main.go`.

## Files to review

- `lib/proscenium/builder.rb` — Ruby FFI struct and function definitions
- `lib/proscenium/resolver.rb` — Ruby resolver that interfaces with Go via FFI
- `main.go` — C struct definitions (in comment block) and exported Go functions

## What to check

1. **Struct field alignment**: Ruby `FFI::Struct` layouts must match the C struct definitions in `main.go`:
   - `Result`: `success` (bool/int), `response` (string/char*), `content_hash` (string/char*)
   - `ResolveResult`: `success` (bool/int), `url_path` (string/char*), `abs_path` (string/char*)
   - `CompileResult`: `success` (bool/int), `messages` (string/char*)
2. **Function signatures**: `attach_function` declarations must match `//export` Go functions:
   - `build_to_string(string, pointer) -> Result`
   - `resolve(string, pointer) -> ResolveResult`
   - `compile(pointer) -> CompileResult`
   - `reset_config() -> void`
3. **Parameter order and types**: Ensure Ruby FFI types (`:string`, `:pointer`, `:bool`, `:void`) correspond to Go C types (`*C.char`, `C.int`)
4. **Return value handling**: Ruby side reads struct fields correctly (e.g. `result[:success]`, `result[:response]`)
5. **Memory management**: `FFI::MemoryPointer.from_string` for config JSON, `C.CString` allocations in Go
6. **New functions**: Any new `//export` function in Go must have a corresponding `attach_function` in Ruby, and vice versa
