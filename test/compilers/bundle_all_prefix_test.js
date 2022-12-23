import { assertStringIncludes, AssertionError } from 'testing/asserts.ts'
import { assertSnapshot } from 'testing/snapshot.ts'
import { beforeEach, describe, it } from 'testing/bdd.ts'
import { join } from 'std/path/mod.ts'

import main from '../../lib/proscenium/compilers/esbuild.js'

const root = join(Deno.cwd(), 'test', 'internal')
const lightningcssBin = join(Deno.cwd(), 'bin', 'lightningcss')

function assertStringExcludes(actual, expected, msg) {
  if (actual.includes(expected)) {
    if (!msg) {
      msg = `actual: "${actual}" expected NOT to contain: "${expected}"`
    }
    throw new AssertionError(msg)
  }
}

describe('bundle-all: prefix', () => {
  beforeEach(() => {
    Deno.env.set('RAILS_ENV', 'test')
    Deno.env.set('PROSCENIUM_TEST', 'test')
  })

  it('js import', async t => {
    const result = await main('lib/bundle_all_import/index.js', {
      root,
      lightningcssBin
    })

    await assertSnapshot(t, new TextDecoder().decode(result))
  })

  it('css', async t => {
    const result = await main('lib/bundle_all_import/index.css', {
      root,
      lightningcssBin
    })

    await assertSnapshot(t, new TextDecoder().decode(result))
  })

  it('tree shaking', async () => {
    const result = await main('lib/bundle_all_import/tree_shaking.js', {
      root,
      lightningcssBin
    })

    const code = new TextDecoder().decode(result)

    assertStringIncludes(code, 'console.log("foo")')
    assertStringIncludes(code, 'console.log("foo2")')
    assertStringExcludes(code, 'console.log("bar")')
  })

  it('with import map', async () => {
    const result = await main('lib/bundle_all_import/import_map.js', {
      root,
      lightningcssBin,
      importMap: 'config/import_maps/simple.json'
    })

    const code = new TextDecoder().decode(result)

    assertStringIncludes(code, 'console.log("/lib/foo.js");')
  })
})
