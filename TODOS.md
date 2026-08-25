# TODOS

## Infrastructure

### Persistent esbuild Context/Rebuild

**What:** Switch `build_to_string`/`resolve` from one-shot `esbuild.Build()` calls to esbuild's persistent `Context()`+`Rebuild()` API so the directory-scan cache survives across calls.

**Why:** Profiling found ~48% of all allocations and 60-90% of CPU in a real build/resolve benchmark come from esbuild-internal re-scanning the same `node_modules` tree from scratch on every single call, because each `Build()` creates a brand-new cache set.

**Context:** Blocked on two open questions: (1) does the Context API support changing `EntryPoints` between `Rebuild()` calls, since Proscenium builds a different entry point per request, and (2) cache invalidation correctness - Proscenium's whole pitch is live on-disk changes reflecting immediately in dev, so a persistent context that caches stale file info would silently break that. Shares root cause (one-shot global state) with the global config refactor - worth scoping together if either is picked up.

**Effort:** L
**Priority:** P3
**Depends on:** None

### Full concurrency audit of esbuild-internal

**What:** A general audit of the vendored esbuild-internal fork (`../esbuild-internal`) for package-level globals unsafe under concurrent use - broader than the specific concurrent-`Build()`/`Resolve()` workload in the global config refactor's Phase 4.

**Why:** Phase 4's audit only exercises the specific code paths Proscenium calls (`Build`, `Resolve`). A general audit would cover the rest of the fork's surface (`Transform`, other entry points) that this refactor doesn't touch but that you maintain.

**Context:** Only came up as a byproduct of scoping the global config refactor's Phase 4. The fork is large; a general audit is a separate, open-ended effort with no clear trigger or deadline. Phase 4's narrower audit already covers the load-bearing case (what Proscenium actually calls) - this would only matter if something outside that surface starts getting exercised concurrently too.

**Effort:** XL
**Priority:** P4
**Depends on:** Global config refactor Phase 4 landing first
