import { assertRejects, assertStringIncludes, assertEquals } from 'testing/asserts.ts'
import { join } from 'path'

import cli from '../lib/proscenium/cli.js'

Deno.env.set('RAILS_ENV', 'test')
Deno.env.set('PROSCENIUM_TEST', 'test')
const cwd = join(Deno.cwd(), 'test', 'internal')

Deno.test('throws without any arguments', async () => {
  await assertRejects(
    async () => await cli(),
    err => assertEquals(err.reason, 'cwdRequired')
  )
})

Deno.test('throws without `entrypoint` argument', async () => {
  await assertRejects(
    async () => await cli(['/foo/bar']),
    err => assertEquals(err.reason, 'entrypointRequired')
  )
})

Deno.test('throws without `builder` argument', async () => {
  await assertRejects(
    async () => await cli(['/foo/bar', 'some/file.js']),
    err => assertEquals(err.reason, 'builderRequired')
  )
})

Deno.test('throws on unknown `cwd`', async () => {
  await assertRejects(
    async () => await cli(['/foo/bar', 'some/file.js', 'js']),
    err => assertEquals(err.reason, 'cwdUnknown')
  )
})

Deno.test('throws on unknown `entrypoint`', async () => {
  await assertRejects(
    async () => await cli([cwd, 'unknown/file.js', 'js']),
    err => assertEquals(err.reason, 'entrypointUnknown')
  )
})

Deno.test('throws on unknown `builder`', async () => {
  await assertRejects(
    async () => await cli([cwd, 'lib/foo.js', 'jss']),
    err => assertEquals(err.reason, 'builderUnknown')
  )
})

Deno.test('Successful JS build', async () => {
  const result = await cli([cwd, 'lib/component.jsx', 'jsx'])

  assertStringIncludes(new TextDecoder().decode(result), 'React.createElement')
})

// Deno.test('Import css from JS', async () => {
//   const result = await init([cwd, 'lib/import_css.js'])

//   assertStringIncludes(
//     new TextDecoder().decode(result),
//     'ele.setAttribute("href", "/app/views/layouts/application.css");'
//   )
// })

// Deno.test('Import css from jsx', async () => {
//   const result = await init([cwd, 'lib/import_css.jsx'], { debug: true })

//   assertStringIncludes(
//     new TextDecoder().decode(result),
//     'ele.setAttribute("href", "/app/views/layouts/application.css");'
//   )
// })

// Deno.test('Import css module', async () => {
//   // const result = await init([cwd, 'lib/import_css_module.js'], { debug: true })
//   const result = await init([cwd, 'lib/import_assert_css.js'], { debug: true })

//   assertStringIncludes(
//     new TextDecoder().decode(result),
//     'ele.setAttribute("href", "/lib/css_module.css");'
//   )
//   assertStringIncludes(new TextDecoder().decode(result), '{ myClass: "123_myClass" }')
// })
