import { assertStringIncludes } from 'std/testing/asserts.ts'
import { assertSnapshot } from 'std/testing/snapshot.ts'
import { join } from 'std/path/mod.ts'
import { beforeEach, describe, it } from 'std/testing/bdd.ts'

import main from '../../lib/proscenium/compilers/esbuild.js'

const root = join(Deno.cwd(), 'test', 'internal')
const lightningcssBin = join(Deno.cwd(), 'bin', 'lightningcss')

describe('import map', () => {
  beforeEach(() => {
    Deno.env.set('RAILS_ENV', 'test')
    Deno.env.set('PROSCENIUM_TEST', 'test')
  })

  it('from json', async t => {
    const result = await main('lib/import_map.js', {
      root,
      lightningcssBin,
      importMap: 'config/import_maps/as.json'
    })

    await assertSnapshot(t, new TextDecoder().decode(result))
  })

  it('from js', async () => {
    const result = await main('lib/import_map_as_js.js', {
      root,
      lightningcssBin,
      importMap: 'config/import_maps/as.js'
    })

    assertStringIncludes(new TextDecoder().decode(result), 'import pkg from "/lib/foo2.js";')
  })

  it('maps imports via trailing slash', async () => {
    const result = await main('lib/component.jsx', {
      root,
      lightningcssBin,
      importMap: 'config/import_maps/trailing_slash_import.json'
    })

    assertStringIncludes(
      new TextDecoder().decode(result),
      'import { jsx } from "/url:https%3A%2F%2Fesm.sh%2Freact%4018.2.0%2Fjsx-runtime"'
    )
  })

  it('resolves imports from a node_module', async t => {
    const result = await main('node_modules/is-ip/index.js', {
      root,
      lightningcssBin,
      importMap: 'config/import_maps/npm.json'
    })

    await assertSnapshot(t, new TextDecoder().decode(result))
  })

  it('supports scopes', async t => {
    const result = await main('lib/import_map/scopes.js', {
      root,
      lightningcssBin,
      importMap: 'config/import_maps/scopes.json'
    })

    await assertSnapshot(t, new TextDecoder().decode(result))
  })

  it('supports aliasing', async t => {
    const result = await main('lib/import_map/aliases.js', {
      root,
      lightningcssBin,
      importMap: 'config/import_maps/aliases.json'
    })

    await assertSnapshot(t, new TextDecoder().decode(result))
  })
})
