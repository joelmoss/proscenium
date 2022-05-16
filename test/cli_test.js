import { assertRejects, assertStringIncludes, assertEquals } from 'std/testing/asserts.ts'
import { beforeEach, describe, it } from 'std/testing/bdd.ts'
import { assertSnapshot } from 'std/testing/snapshot.ts'
import { join } from 'std/path/mod.ts'

import cli from '../lib/proscenium/cli.js'

const cwd = join(Deno.cwd(), 'test', 'internal')

describe('cli', () => {
  beforeEach(() => {
    Deno.env.set('RAILS_ENV', 'test')
    Deno.env.set('PROSCENIUM_TEST', 'test')
  })

  it('throws without any arguments', async () => {
    await assertRejects(
      async () => await cli(),
      err => assertEquals(err.reason, 'cwdRequired')
    )
  })

  it('throws without `entrypoint` argument', async () => {
    await assertRejects(
      async () => await cli(['/foo/bar']),
      err => assertEquals(err.reason, 'entrypointRequired')
    )
  })

  it('throws without `builder` argument', async () => {
    await assertRejects(
      async () => await cli(['/foo/bar', 'some/file.js']),
      err => assertEquals(err.reason, 'builderRequired')
    )
  })

  it('throws on unknown `cwd`', async () => {
    await assertRejects(
      async () => await cli(['/foo/bar', 'some/file.js', 'js']),
      err => assertEquals(err.reason, 'cwdUnknown')
    )
  })

  it('throws on unknown `entrypoint`', async () => {
    await assertRejects(
      async () => await cli([cwd, 'unknown/file.js', 'js']),
      err => assertEquals(err.reason, 'entrypointUnknown')
    )
  })

  it('throws on unknown `builder`', async () => {
    await assertRejects(
      async () => await cli([cwd, 'lib/foo.js', 'jss']),
      err => assertEquals(err.reason, 'builderUnknown')
    )
  })

  it('Successful JSX build', async t => {
    const result = await cli([cwd, 'lib/component.jsx', 'esbuild'])

    assertStringIncludes(new TextDecoder().decode(result), 'createElement("div", null, "Hello")')
  })

  it('jsx should inject react', async () => {
    const result = await cli([cwd, 'lib/component.jsx', 'esbuild'])

    assertStringIncludes(
      new TextDecoder().decode(result),
      'import { createElement, Fragment } from "react";'
    )
  })

  it('defines process.env.NODE_ENV', async () => {
    const result = await cli([cwd, 'lib/node_env.js', 'esbuild'])

    assertStringIncludes(new TextDecoder().decode(result), '"process.env.NODE_ENV=", "test"')
  })

  it('Import bare module', async () => {
    const result = await cli([cwd, 'lib/import_node_module.js', 'esbuild'])

    assertStringIncludes(
      new TextDecoder().decode(result),
      'import { useIbiza } from "/node_modules/.pnpm/ibiza@1.3.1/node_modules/ibiza/dist/ibiza.modern.js";'
    )
  })

  it('Import unknown bare module', async () => {
    const result = await cli([cwd, 'lib/import_unknown_node_module.js', 'esbuild'])

    assertStringIncludes(new TextDecoder().decode(result), 'import unknown from "unknown";')
  })

  it('Import relative module', async () => {
    const result = await cli([cwd, 'lib/import_relative_module.js', 'esbuild'])

    assertStringIncludes(new TextDecoder().decode(result), 'import "/lib/foo.js";')
  })

  it('Import absolute module', async () => {
    const result = await cli([cwd, 'lib/import_absolute_module.js', 'esbuild'])

    assertStringIncludes(new TextDecoder().decode(result), 'import "/lib/foo.js";')
  })

  it('Import remote module', async () => {
    const result = await cli([cwd, 'lib/import_remote_module.js', 'esbuild'])

    assertStringIncludes(
      new TextDecoder().decode(result),
      'import axios from "https://cdnjs.cloudflare.com/ajax/libs/axios/0.24.0/axios.min.js";'
    )
  })

  it('js sourcemap', async t => {
    const result = await cli([cwd, 'lib/foo.js.map', 'esbuild'])

    assertSnapshot(t, new TextDecoder().decode(result))
  })

  it('Import relative module without extension', async () => {
    const result = await cli([cwd, 'lib/import_relative_module_without_extension.js', 'esbuild'])
    assertStringIncludes(new TextDecoder().decode(result), 'import foo from "/lib/foo.js";')
  })

  it('Import absolute module without extension', async () => {
    const result = await cli([cwd, 'lib/import_absolute_module_without_extension.js', 'esbuild'])
    assertStringIncludes(new TextDecoder().decode(result), 'import foo from "/lib/foo.js";')
  })

  it('css', async t => {
    const result = await cli([cwd, 'app/views/layouts/application.css', 'parcelcss'])

    assertSnapshot(t, new TextDecoder().decode(result))
  })

  it('css map', async t => {
    const result = await cli([cwd, 'app/views/layouts/application.css.map', 'parcelcss'])

    assertSnapshot(t, new TextDecoder().decode(result))
  })

  // it('Import css from JS', async () => {
  //   const result = await cli([cwd, 'lib/import_css.js', 'esbuild'])

  //   assertStringIncludes(
  //     new TextDecoder().decode(result),
  //     'ele.setAttribute("href", "/app/views/layouts/application.css");'
  //   )
  // })

  // it('Import css from jsx', async () => {
  //   const result = await init([cwd, 'lib/import_css.jsx'], { debug: true })

  //   assertStringIncludes(
  //     new TextDecoder().decode(result),
  //     'ele.setAttribute("href", "/app/views/layouts/application.css");'
  //   )
  // })

  // it('Import css module', async () => {
  //   // const result = await init([cwd, 'lib/import_css_module.js'], { debug: true })
  //   const result = await init([cwd, 'lib/import_assert_css.js'], { debug: true })

  //   assertStringIncludes(
  //     new TextDecoder().decode(result),
  //     'ele.setAttribute("href", "/lib/css_module.css");'
  //   )
  //   assertStringIncludes(new TextDecoder().decode(result), '{ myClass: "123_myClass" }')
  // })
})
