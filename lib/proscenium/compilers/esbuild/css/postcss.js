import { expandGlob } from 'std/fs/mod.ts'
import postcss from 'postcss'

import { readFile } from '../../../utils.js'

export default async (path, options) => {
  const mixinPaths = options.mixinPaths || []
  let tmpFile
  let contents

  const mixinFiles = []
  for (const mixinPath of mixinPaths) {
    for await (const file of expandGlob('**/*.mixin.css', { root: mixinPath, globstar: true })) {
      mixinFiles.push(file.path)
    }
  }

  // Only process mixins with PostCSS if there are any mixin files.
  if (mixinFiles.length > 0) {
    tmpFile = await Deno.makeTempFile()
    contents = await readFile(path)

    const result = await postcss([mixinsPlugin({ mixinFiles })]).process(contents, { from: path })
    contents = result.css
  }

  return [tmpFile, contents]
}

const mixinsPlugin = (opts = {}) => {
  return {
    postcssPlugin: 'mixins',

    prepare() {
      const mixins = {}

      return {
        async Once(_, helpers) {
          for (const path of opts.mixinFiles) {
            const content = await readFile(path)
            const root = helpers.parse(content, { from: path })

            root.walkAtRules('define-mixin', atrule => {
              mixins[atrule.params] = atrule
            })
          }
        },

        AtRule: {
          mixin: (rule, helpers) => {
            const mixin = mixins[rule.params]

            if (!mixin) {
              throw rule.error(`Undefined mixin '${rule.params}'`)
            }

            const proxy = new helpers.Root()
            for (let i = 0; i < mixin.nodes.length; i++) {
              const node = mixin.nodes[i].clone()
              delete node.raws.before
              proxy.append(node)
            }

            rule.parent.insertBefore(rule, proxy)

            if (rule.parent) rule.remove()
          }
        }
      }
    }
  }
}
