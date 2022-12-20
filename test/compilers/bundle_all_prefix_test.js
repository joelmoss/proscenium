import { assertStringIncludes, AssertionError } from 'testing/asserts.ts'
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

  it('js import', async () => {
    const result = await main('lib/bundle_all_import/index.js', {
      root,
      lightningcssBin
    })

    const code = new TextDecoder().decode(result)

    assertStringIncludes(code, 'console.log(1)')
    assertStringIncludes(code, 'console.log(2)')
    assertStringIncludes(code, 'console.log(3)')
    assertStringIncludes(code, 'import "/lib/foo.js";')
  })

  it('tree shaking', async () => {
    const result = await main('lib/bundle_all_import/tree_shaking.js', {
      root,
      lightningcssBin
    })

    const code = new TextDecoder().decode(result)

    assertStringIncludes(code, 'console.log("foo")')
    assertStringExcludes(code, 'console.log("bar")')
  })

  // TODO:
  it.ignore('with import map', async () => {
    const result = await main('lib/bundle_all_import/import_map.js', {
      root,
      lightningcssBin,
      importMap: 'config/import_maps/simple.json',
      debug: true
    })

    const code = new TextDecoder().decode(result)

    assertStringIncludes(code, 'console.log("foo")')
    assertStringExcludes(code, 'console.log("bar")')
  })
})
