import { join } from 'std/path/mod.ts'

import compile from './esbuild.js'

const root = join(Deno.cwd(), 'test', 'internal')

Deno.bench('esbuild js', async () => {
  await compile(['lib/foo.js'], { root })
})

Deno.bench('esbuild css', async () => {
  await compile(['lib/foo.css'], { root })
})
