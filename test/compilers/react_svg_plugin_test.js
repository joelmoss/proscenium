import { assertSnapshot } from 'std/testing/snapshot.ts'
import { join } from 'std/path/mod.ts'
import { beforeEach, describe, it } from 'std/testing/bdd.ts'

import main from '../../lib/proscenium/compilers/esbuild.js'

const root = join(Deno.cwd(), 'test', 'internal')
const lightningcssBin = join(Deno.cwd(), 'bin', 'lightningcss')

describe('reactSvgPlugin', () => {
  beforeEach(() => {
    Deno.env.set('RAILS_ENV', 'test')
    Deno.env.set('PROSCENIUM_TEST', 'test')
  })

  it('returns a React component when imported from jsx', async t => {
    const result = await main('lib/svg/component.jsx', {
      root,
      lightningcssBin
    })

    await assertSnapshot(t, new TextDecoder().decode(result))
  })

  it('supports import map', async t => {
    const result = await main('lib/svg/with_import_map.jsx', {
      root,
      importMap: 'config/import_maps/svg.json',
      lightningcssBin
    })

    await assertSnapshot(t, new TextDecoder().decode(result))
  })
})
