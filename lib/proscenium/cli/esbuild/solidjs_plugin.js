import { basename } from 'std/path/mod.ts'
import { transformAsync } from 'https://esm.sh/@babel/core'
import solid from 'https://esm.sh/babel-preset-solid'

import { setup } from '../utils.js'

export default setup('solidjs', () => {
  return {
    onLoad: {
      filter: /\.jsx$/,
      async callback(args) {
        const source = await Deno.readTextFile(args.path)

        const { code } = await transformAsync(source, {
          presets: [solid],
          filename: basename(args.path),
          sourceMaps: 'inline'
        })

        return { contents: code, loader: 'js' }
      }
    }
  }
})
