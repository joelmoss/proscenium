import { crypto } from 'std/crypto/mod.ts'
import { join, resolve, dirname, fromFileUrl } from 'std/path/mod.ts'

import setup from './setup_plugin.js'

export default setup('css', async build => {
  const cwd = build.initialOptions.absWorkingDir
  const parcelBin = resolve(dirname(fromFileUrl(import.meta.url)), '../../../../bin/parcel_css')

  let customMedia
  try {
    customMedia = await Deno.readTextFile(join(cwd, 'config', 'custom_media_queries.css'))
  } catch {
    // do nothing, as we don't require custom media.
  }

  return {
    onLoad: {
      filter: /\.css$/,
      async callback(args) {
        let path = args.path
        const isCssModule = args.path.endsWith('.module.css')
        let cmd = [parcelBin, '--nesting', '--targets', '>= 0.25%']

        if (customMedia) {
          cmd.push('--custom-media')

          path = await Deno.makeTempFile()
          await Deno.writeTextFile(path, (await Deno.readTextFile(args.path)) + customMedia)
        }

        if (isCssModule) {
          const hash = await digest(args.path.slice(cwd.length))
          cmd = cmd.concat(['--css-modules', '--css-modules-pattern', `[local]${hash}`])
        }

        const p = Deno.run({
          cmd: [...cmd, path],
          stdout: 'piped',
          stderr: 'piped'
        })

        const { code } = await p.status()
        const rawOutput = await p.output()
        const rawError = await p.stderrOutput()

        if (code === 0) {
          const contents = new TextDecoder().decode(rawOutput)
          return { loader: 'css', contents: isCssModule ? JSON.parse(contents).code : contents }
        } else {
          const errorString = new TextDecoder().decode(rawError)
          throw errorString
        }
      }
    }
  }
})

async function digest(value) {
  value = new TextEncoder().encode(value)
  const view = new DataView(await crypto.subtle.digest('SHA-1', value))

  let hexCodes = ''
  for (let index = 0; index < view.byteLength; index += 4) {
    hexCodes += view.getUint32(index).toString(16).padStart(8, '0')
  }

  return hexCodes.slice(0, 8)
}
