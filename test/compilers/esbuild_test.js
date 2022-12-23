import { assertRejects } from 'testing/asserts.ts'
import { assertSnapshot } from 'testing/snapshot.ts'
import { beforeEach, describe, it } from 'testing/bdd.ts'
import { join } from 'std/path/mod.ts'

import main from '../../lib/proscenium/compilers/esbuild.js'
import ArgumentError from '../../lib/proscenium/compilers/esbuild/argument_error.js'

const root = join(Deno.cwd(), 'test', 'internal')
const lightningcssBin = join(Deno.cwd(), 'bin', 'lightningcss')

describe('compilers/esbuild', () => {
  beforeEach(() => {
    Deno.env.set('RAILS_ENV', 'test')
    Deno.env.set('PROSCENIUM_TEST', 'test')
  })

  it('throws without any arguments', async () => {
    await assertRejects(async () => await main(), ArgumentError, 'pathRequired')
  })

  it('throws without root option', async () => {
    await assertRejects(async () => await main('**/*.js'), ArgumentError, 'rootRequired')
  })

  it('throws without lightningcssBin option', async () => {
    await assertRejects(
      async () => await main('**/*.js', { root: 'foo/bar' }),
      ArgumentError,
      'lightningcssBinRequired:'
    )
  })

  it('Successful JSX build', async t => {
    const result = await main('lib/component.jsx', { root, lightningcssBin })

    await assertSnapshot(t, new TextDecoder().decode(result))
  })

  it('Import bare module', async t => {
    const result = await main('lib/import_node_module.js', { root, lightningcssBin })

    await assertSnapshot(t, new TextDecoder().decode(result))
  })

  it('invalid URL', async t => {
    const result = await main('url:https://unpkg.com/open-props@1.5.3/red.min.css', {
      root,
      lightningcssBin
    })

    await assertSnapshot(t, new TextDecoder().decode(result))
  })

  it('allows returns error on unknown bare module', async t => {
    const result = await main('lib/import_unknown_node_module.js', { root, lightningcssBin })

    await assertSnapshot(t, result)
  })

  it('resolves nested node modules', async t => {
    const result = await main('node_modules/@react-aria/button', { root, lightningcssBin })

    await assertSnapshot(t, new TextDecoder().decode(result))
  })

  it('Import relative module', async t => {
    const result = await main('lib/import_relative_module.js', { root, lightningcssBin })

    await assertSnapshot(t, new TextDecoder().decode(result))
  })

  it('Import absolute module', async t => {
    const result = await main('lib/import_absolute_module.js', { root, lightningcssBin })

    await assertSnapshot(t, new TextDecoder().decode(result))
  })

  it('Import remote module', async t => {
    const result = await main('lib/import_remote_module.js', { root, lightningcssBin })

    await assertSnapshot(t, new TextDecoder().decode(result))
  })

  it('npm module with relative import', async t => {
    const result = await main('lib/npm_module_with_relative_import.js', { root, lightningcssBin })

    await assertSnapshot(t, new TextDecoder().decode(result))
  })

  it('Import relative module without extension', async t => {
    const result = await main('lib/import_relative_module_without_extension.js', {
      root,
      lightningcssBin
    })

    await assertSnapshot(t, new TextDecoder().decode(result))
  })

  it('Import absolute module without extension', async t => {
    const result = await main('lib/import_absolute_module_without_extension.js', {
      root,
      lightningcssBin
    })

    await assertSnapshot(t, new TextDecoder().decode(result))
  })

  it('Import css module from JS', async t => {
    const result = await main('lib/import_css_module.js', {
      root,
      lightningcssBin,
      cssMixinPaths: [join(root, 'lib')]
    })

    await assertSnapshot(t, new TextDecoder().decode(result))
  })

  it('de-dupes side loaded ViewComponent default stylesheet - regular', async t => {
    const result = await main('app/components/basic_react_component.jsx', {
      root,
      lightningcssBin
    })

    await assertSnapshot(t, new TextDecoder().decode(result))
  })

  it('de-dupes side loaded ViewComponent default stylesheet - sidecar', async t => {
    const result = await main('app/components/basic_react/component.jsx', {
      root,
      lightningcssBin
    })

    await assertSnapshot(t, new TextDecoder().decode(result))
  })

  it('Import css from JS', async t => {
    const result = await main('lib/import_css.js', {
      root,
      lightningcssBin,
      cssMixinPaths: [join(root, 'lib')]
    })

    await assertSnapshot(t, new TextDecoder().decode(result))
  })

  it('Import css from jsx', async t => {
    const result = await main('lib/import_css.jsx', {
      root,
      lightningcssBin,
      cssMixinPaths: [join(root, 'lib')]
    })

    await assertSnapshot(t, new TextDecoder().decode(result))
  })

  describe('postcss', () => {
    it('supports mixins', async t => {
      const result = await main('lib/with_mixins.css', {
        root,
        lightningcssBin,
        cssMixinPaths: [join(root, 'lib')]
      })

      await assertSnapshot(t, new TextDecoder().decode(result))
    })

    it('cssMixinPaths option', async t => {
      const result = await main('lib/with_mixins_from_alternative_path.css', {
        root,
        lightningcssBin,
        cssMixinPaths: [join(root, 'lib'), join(root, 'config')]
      })

      await assertSnapshot(t, new TextDecoder().decode(result))
    })
  })
})
