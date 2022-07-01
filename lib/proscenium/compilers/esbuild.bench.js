import { join } from 'std/path/mod.ts'

import compile from './esbuild.js'

const cwd = join(Deno.cwd(), 'test', 'internal')

Deno.bench('esbuild', async () => {
  await compile(cwd, 'lib/foo.js')
})
