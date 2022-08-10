import { basename } from 'std/path/mod.ts'
import { transformAsync } from '@babel/core'
import solid from 'babel-preset-solid'

import { setup } from './setup_plugin.js'

export default setup('solidjs', () => {
  return [
    {
      type: 'onLoad',
      filter: /\.jsx$/,
      async callback(args) {
        const source = await Deno.readTextFile(args.path)

        const { code } = await transformAsync(source, {
          presets: [solid],
          filename: basename(args.path)
        })

        return { contents: code, loader: 'js' }
      }
    }
  ]
})
