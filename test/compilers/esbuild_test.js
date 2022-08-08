import { assertRejects } from 'std/testing/asserts.ts'
import { assertSnapshot } from 'std/testing/snapshot.ts'
import { join } from 'std/path/mod.ts'
import { beforeEach, describe, it } from 'std/testing/bdd.ts'

import main from '../../lib/proscenium/compilers/esbuild.js'
import ArgumentError from '../../lib/proscenium/compilers/esbuild/argument_error.js'

const root = join(Deno.cwd(), 'test', 'internal')

describe('compilers/esbuild', () => {
  beforeEach(() => {
    Deno.env.set('RAILS_ENV', 'test')
    Deno.env.set('PROSCENIUM_TEST', 'test')
  })

  it('throws without any arguments', async () => {
    await assertRejects(async () => await main(), ArgumentError, 'pathsRequired')
  })

  it('throws without array of paths', async () => {
    await assertRejects(async () => await main('foo/bar'), ArgumentError, 'pathsRequired')
  })

  it('throws without root option', async () => {
    await assertRejects(async () => await main(['**/*.js']), ArgumentError, 'rootRequired')
  })

  it('throws with unknown root', async () => {
    await assertRejects(
      async () => await main(['**/*.js'], { root: 'foo/bar' }),
      ArgumentError,
      'rootUnknown'
    )
  })

  it('unknown path', { ignore: true }, async t => {
    await assertRejects(
      async () => await main(['lib/unknown.jsx'], { root }),
      Error,
      'Could not resolve'
    )
  })

  it('Successful JSX build', async t => {
    const result = await main(['lib/component.jsx'], { root })

    await assertSnapshot(t, new TextDecoder().decode(result))
  })

  it('Import bare module', async t => {
    const result = await main(['lib/import_node_module.js'], { root })

    await assertSnapshot(t, new TextDecoder().decode(result))
  })

  it('allows unknown bare module', async t => {
    const result = await main(['lib/import_unknown_node_module.js'], { root })

    await assertSnapshot(t, new TextDecoder().decode(result))
  })

  it('Import relative module', async t => {
    const result = await main(['lib/import_relative_module.js'], { root })

    await assertSnapshot(t, new TextDecoder().decode(result))
  })

  it('Import absolute module', async t => {
    const result = await main(['lib/import_absolute_module.js'], { root })

    await assertSnapshot(t, new TextDecoder().decode(result))
  })

  it('Import remote module', async t => {
    const result = await main(['lib/import_remote_module.js'], { root })

    await assertSnapshot(t, new TextDecoder().decode(result))
  })

  it('import map', async t => {
    const result = await main(['lib/import_map.js'], { root })

    await assertSnapshot(t, new TextDecoder().decode(result))
  })

  it('Import relative module without extension', async t => {
    const result = await main(['lib/import_relative_module_without_extension.js'], { root })

    await assertSnapshot(t, new TextDecoder().decode(result))
  })

  it('Import absolute module without extension', async t => {
    const result = await main(['lib/import_absolute_module_without_extension.js'], { root })

    await assertSnapshot(t, new TextDecoder().decode(result))
  })

  it('Import css module from JS', async t => {
    const result = await main(['lib/import_css_module.js'], { root })

    await assertSnapshot(t, new TextDecoder().decode(result))
  })

  it('Import css from JS', async t => {
    const result = await main(['lib/import_css.js'], { root })

    await assertSnapshot(t, new TextDecoder().decode(result))
  })

  it('Import css from jsx', async t => {
    const result = await main(['lib/import_css.jsx'], { root })

    await assertSnapshot(t, new TextDecoder().decode(result))
  })

  it('bundled js import', async t => {
    const result = await main(['lib/bundle_import.js'], { root })

    await assertSnapshot(t, new TextDecoder().decode(result))
  })

  it('bundled css import', async t => {
    const result = await main(['lib/bundle_import.css'], { root })

    await assertSnapshot(t, new TextDecoder().decode(result))
  })
})
