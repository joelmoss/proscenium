import { join } from 'std/path/mod.ts'

import compile from './esbuild.js'

const root = join(Deno.cwd(), 'test', 'internal')

Deno.bench('esbuild', async () => {
  await compile(['lib/foo.js'], { root })
})
