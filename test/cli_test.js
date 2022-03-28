import { assertRejects, assertStringIncludes } from 'https://deno.land/std/testing/asserts.ts'
import { join } from 'https://deno.land/std/path/mod.ts'

import { init } from '../lib/proscenium/cli.js'

Deno.env.set('RAILS_ENV', 'test')
Deno.env.set('PROSCENIUM_TEST', 'test')
const cwd = join(Deno.cwd(), 'test', 'internal')

Deno.test('throws without any arguments', () => {
  assertRejects(() => init(), TypeError)
})

Deno.test('throws without `cwd` argument', () => {
  assertRejects(() => init('/foo/bar'), TypeError)
})

Deno.test('throws without `entrypoint` argument', () => {
  assertRejects(() => init(['/foo/bar', 'comp.js']), TypeError)
})

Deno.test('Throws on unknown cwd', () => {
  assertRejects(() => init(['/foo/bar', 'comp.js']), TypeError)
})

Deno.test('Throws on unknown entrypoint', () => {
  assertRejects(() => init([cwd, 'comp.js']), TypeError)
})

Deno.test('Successful JS build', async () => {
  const result = await init([cwd, 'app/views/layouts/application.js'])

  assertStringIncludes(
    new TextDecoder().decode(result),
    'console.log("app/views/layouts/application.js")'
  )
})

Deno.test('Import css from JS', async () => {
  const result = await init([cwd, 'lib/import_css.js'])

  assertStringIncludes(
    new TextDecoder().decode(result),
    'ele.setAttribute("href", "/app/views/layouts/application.css");'
  )
})

Deno.test('Import css from jsx', async () => {
  const result = await init([cwd, 'lib/import_css.jsx'], { debug: true })

  assertStringIncludes(
    new TextDecoder().decode(result),
    'ele.setAttribute("href", "/app/views/layouts/application.css");'
  )
})

Deno.test('Import css module', { only: true }, async () => {
  // const result = await init([cwd, 'lib/import_css_module.js'], { debug: true })
  const result = await init([cwd, 'lib/import_assert_css.js'], { debug: true })

  assertStringIncludes(
    new TextDecoder().decode(result),
    'ele.setAttribute("href", "/lib/css_module.css");'
  )
  assertStringIncludes(new TextDecoder().decode(result), '{ myClass: "123_myClass" }')
})
