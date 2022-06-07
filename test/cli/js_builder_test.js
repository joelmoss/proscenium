import { assert, assertRejects, assertStringIncludes } from 'std/testing/asserts.ts'
import { join } from 'std/path/mod.ts'

import builder from '../../lib/proscenium/cli/js_builder.js'

Deno.env.set('RAILS_ENV', 'test')
Deno.env.set('PROSCENIUM_TEST', 'test')
const cwd = join(Deno.cwd(), 'test', 'internal')

Deno.test('Throws on unresolvable entrypoint', async () => {
  await assertRejects(async () => {
    await builder(cwd, 'unknown.js')
  })
})

Deno.test('Successful JS build', async () => {
  assert(await builder(cwd, 'app/views/layouts/application.js'))
})

Deno.test('Successful CSS build', async () => {
  assert(await builder(cwd, 'app/views/layouts/application.css', { debug: true }))
})

Deno.test('Failed build', async () => {
  await assertRejects(async () => {
    await builder(cwd, 'lib/includes_error.js')
  })
})

Deno.test('Import relative module without extension', async () => {
  const result = await builder(cwd, 'lib/import_relative_module_without_extension.js')
  assertStringIncludes(result.outputFiles.at(0).text, 'import foo from "/lib/foo.js";')
})

Deno.test('Import absolute module without extension', async () => {
  const result = await builder(cwd, 'lib/import_absolute_module_without_extension.js')
  assertStringIncludes(result.outputFiles.at(0).text, 'import foo from "/lib/foo.js";')
})

Deno.test('Import bare module', async () => {
  const result = await builder(cwd, 'lib/import_node_module.js')
  assertStringIncludes(
    result.outputFiles.at(0).text,
    'import bogus from "/node_modules/bogus/index.js";'
  )
})

Deno.test('Import relative module', async () => {
  const result = await builder(cwd, 'lib/import_relative_module.js')

  assertStringIncludes(
    result.outputFiles.at(0).text,
    'import bogus from "/node_modules/bogus/index.js";'
  )
})

Deno.test('Import absolute module', async () => {
  const result = await builder(cwd, 'lib/import_absolute_module.js')

  assertStringIncludes(
    result.outputFiles.at(0).text,
    'import bogus from "/node_modules/bogus/index.js";'
  )
})

Deno.test('Import remote module', async () => {
  const result = await builder(cwd, 'lib/import_remote_module.js')

  assertStringIncludes(
    result.outputFiles.at(0).text,
    'import axios from "https://cdnjs.cloudflare.com/ajax/libs/axios/0.24.0/axios.min.js";'
  )
})

Deno.test('Import css from JS', async () => {
  const result = await builder([cwd, 'lib/import_assert_css.js'], { debug: true })
  console.log(new TextDecoder().decode(result))

  assertStringIncludes(
    result.outputFiles.at(0).text,
    'appendStylesheet_default("/app/views/layouts/application.css")'
  )
})

Deno.test('Dynamic import css from JS', async () => {
  const result = await builder([cwd, 'lib/dynamic_import_assert_css.js'], { debug: true })
  console.log(new TextDecoder().decode(result))

  assertStringIncludes(
    result.outputFiles.at(0).text,
    'appendStylesheet_default("/app/views/layouts/application.css")'
  )
})

Deno.test('Import of dynamic import css from JS', { only: true }, async () => {
  const result = await builder([cwd, 'lib/import_dynamic_import_assert_css.js'], { debug: true })
  console.log(new TextDecoder().decode(result))

  assertStringIncludes(new TextDecoder().decode(result), 'await adoptCssModules(')
})

Deno.test('Import css from JS', { ignore: true }, async () => {
  const result = await builder(cwd, 'lib/import_css.js')

  assertStringIncludes(
    result.outputFiles.at(0).text,
    'appendStylesheet_default("/app/views/layouts/application.css")'
  )
})

Deno.test('Import css from jsx', { ignore: true }, async () => {
  const result = await builder(cwd, 'lib/import_css.jsx', { debug: true })

  assertStringIncludes(
    result.outputFiles.at(0).text,
    'appendStylesheet_default("/app/views/layouts/application.css")'
  )
})
