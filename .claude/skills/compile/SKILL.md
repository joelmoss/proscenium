---
name: compile
description: Compile the Go shared library for local development
---

# Compile Go Binary

Compile the Go shared library needed for Ruby tests and development.

## Steps

1. Run `bundle exec rake compile:local`
2. Verify the binary exists at `lib/proscenium/ext/proscenium`
3. Report success or failure
