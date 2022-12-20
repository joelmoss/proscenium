import { assertSnapshot } from 'std/testing/snapshot.ts'
import { join } from 'std/path/mod.ts'
import { beforeEach, describe, it } from 'std/testing/bdd.ts'

import main from '../../lib/proscenium/compilers/esbuild.js'

const root = join(Deno.cwd(), 'test', 'internal')
const lightningcssBin = join(Deno.cwd(), 'bin', 'lightningcss')

describe('bundle-all: prefix', () => {
  beforeEach(() => {
    Deno.env.set('RAILS_ENV', 'test')
    Deno.env.set('PROSCENIUM_TEST', 'test')
  })

  it('js import', async t => {
    const result = await main('lib/bundle_all_import/index.js', {
      root,
      lightningcssBin,
      importMap: 'config/import_maps/bundled.json'
    })

    await assertSnapshot(t, new TextDecoder().decode(result))
  })
})
