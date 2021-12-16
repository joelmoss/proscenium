import { assert, assertRejects } from 'https://deno.land/std/testing/asserts.ts'
import { join } from 'https://deno.land/std/path/mod.ts'
import builder from '../lib/proscenium/builder.js'

const cwd = join(Deno.cwd(), 'test', 'internal')

Deno.test('throws without any arguments', () => {
  assertRejects(() => builder(), TypeError)
})

Deno.test('throws without `entrypoint` argument', () => {
  assertRejects(() => builder('/foo/bar'), TypeError)
})

Deno.test('Throws on unresolvable entrypoint', async () => {
  await assertRejects(async () => {
    await builder(cwd, 'unknown.js')
  })
})

Deno.test('Returns esbuild results', async () => {
  assert(await builder(cwd, 'app/views/layouts/application.js'))
})

Deno.test('build errors are thrown', async () => {
  await assertRejects(async () => {
    await builder(cwd, 'lib/includes_error.js')
  })
})
