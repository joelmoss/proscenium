import { join } from 'std/path/mod.ts'
import { expandGlob } from 'std/fs/mod.ts'
import deepmerge from 'deepmerge'
import camelcaseKeys from 'camelcase-keys'
import YAML from 'yaml'

import setup from './setup_plugin.js'
import { readFile } from '../../utils.js'

// Export environment variables as named exports only. You can also import from `env:ENV_VAR_NAME`,
// which will return the value of the environment variable as the default export. This allows you to
// safely import a variable regardless of its existence.
export default setup('i18n', build => {
  const cwd = build.initialOptions.absWorkingDir
  const root = join(cwd, 'config', 'locales')

  return [
    {
      type: 'onResolve',
      filter: /@proscenium\/i18n$/,
      callback({ path }) {
        return { path, namespace: 'i18n' }
      }
    },

    {
      type: 'onLoad',
      filter: /.*/,
      namespace: 'i18n',
      async callback() {
        let translations = {}

        for await (const file of expandGlob('**/*.yml', { root, globstar: true })) {
          const yaml = YAML.parse(await readFile(file.path))
          translations = deepmerge(translations, camelcaseKeys(yaml, { deep: true }))
        }

        return {
          loader: 'json',
          contents: JSON.stringify(translations.en)
        }
      }
    }
  ]
})
