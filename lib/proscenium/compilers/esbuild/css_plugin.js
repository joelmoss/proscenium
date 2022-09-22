import { crypto } from 'std/crypto/mod.ts'
import { join, resolve, dirname, fromFileUrl } from 'std/path/mod.ts'

import postcss from './css/postcss.js'
import setup from './setup_plugin.js'

export default setup('css', async build => {
  const cwd = build.initialOptions.absWorkingDir
  const lightningcssBin = resolve(
    dirname(fromFileUrl(import.meta.url)),
    '../../../../bin/lightningcss'
  )

  let customMedia
  try {
    customMedia = await Deno.readTextFile(join(cwd, 'config', 'custom_media_queries.css'))
  } catch {
    // do nothing, as we don't require custom media.
  }

  return [
    {
      type: 'onLoad',
      filter: /\.css$/,
      namespace: 'file',
      async callback(args) {
        const isCssModule = args.path.endsWith('.module.css')
        let cmd = [
          lightningcssBin,
          '--nesting',
          '--error-recovery',
          args.pluginData?.importedFromJs && '--minify',
          '--targets',
          '>= 0.25%'
        ].filter(Boolean)

        // This will process the CSS with Postcss only if it needs to.
        let [tmpFile, contents] = await postcss(cwd, args.path)

        // As custom media are defined in their own file, we have to append the file contents to our
        // stylesheet, so that the custom media can be used.
        if (customMedia) {
          cmd.push('--custom-media')

          if (!tmpFile && !contents) {
            tmpFile = await Deno.makeTempFile()
            contents = await Deno.readTextFile(args.path)
          }

          contents += customMedia
        }

        if (tmpFile && contents) {
          await Deno.writeTextFile(tmpFile, contents)
        }

        const hash = await digest(args.path.slice(cwd.length))
        if (isCssModule) {
          cmd = cmd.concat(['--css-modules', '--css-modules-pattern', `[local]${hash}`])
        }

        const p = Deno.run({
          cmd: [...cmd, tmpFile || args.path],
          stdout: 'piped',
          stderr: 'piped'
        })

        const { code } = await p.status()
        const rawOutput = await p.output()
        const rawError = await p.stderrOutput()

        // Even though Deno docs say that reading the outputs (above) closes their pipes, warnings
        // are raised during tests that the child process have not been closed. So we manually close
        // here.
        p.close()

        if (code === 0) {
          let contents = new TextDecoder().decode(rawOutput)
          if (isCssModule) {
            contents = JSON.parse(contents)
          }

          if (args.pluginData?.importedFromJs) {
            let code

            if (isCssModule) {
              code = contents.code
            } else {
              code = contents
            }

            const mod = [
              `let e = document.querySelector('#_${hash}');`,
              'if (!e) {',
              "e = document.createElement('style');",
              `e.id = '_${hash}';`,
              'document.head.appendChild(e);',
              `e.appendChild(document.createTextNode(\`${code}\`));`,
              '}'
            ]

            if (isCssModule) {
              const classes = {}
              for (const key in contents.exports) {
                if (Object.hasOwnProperty.call(contents.exports, key)) {
                  classes[key] = contents.exports[key].name
                }
              }
              mod.push(`export default ${JSON.stringify(classes)};`)
            }

            // We are importing from JS, so return the entire result from LightningCSS via the js
            // loader.
            return {
              resolveDir: cwd,
              loader: 'js',
              contents: mod.join('')
            }
          }

          return { loader: 'css', contents: isCssModule ? contents.code : contents }
        } else {
          const errorString = new TextDecoder().decode(rawError)
          throw errorString
        }
      }
    }
  ]
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
