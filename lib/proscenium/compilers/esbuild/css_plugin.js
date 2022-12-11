import { crypto } from 'std/crypto/mod.ts'
import { join, dirname, basename } from 'std/path/mod.ts'

import { fileExists } from '../../utils.js'
import postcss from './css/postcss.js'
import setup from './setup_plugin.js'

export default setup('css', async (build, options) => {
  const cwd = build.initialOptions.absWorkingDir
  const customMedia = await getCustomMedia(cwd)

  return [
    {
      type: 'onLoad',
      filter: /\.css$/,
      namespace: 'file',
      async callback(args) {
        // Use the real (non-symlinked) path to calculate the hash digest for CSS modules. This
        // ensures that it is the same across platforms.
        const hash = await digest(await Deno.realPath(args.path))

        const relativePath = args.path.slice(cwd.length)
        const isCssModule = args.path.endsWith('.module.css')

        // If path is a CSS module, imported from JS, and a side-loaded ViewComponent stylesheet,
        // simply return a JS proxy of the class names. The stylesheet itself will have already been
        // side loaded. This avoids compiling the CSS all over again.
        if (isCssModule && args.pluginData?.importedFromJs && (await isViewComponent(args.path))) {
          return {
            resolveDir: cwd,
            loader: 'js',
            contents: cssModulesProxyTemplate(hash)
          }
        }

        let cmd = [
          options.lightningcssBin,
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

        // Success!
        if (code === 0) {
          let contents = new TextDecoder().decode(rawOutput)
          if (isCssModule) {
            contents = JSON.parse(contents)
          }

          // If stylesheet is imported from JS, then we return JS code that appends the stylesheet
          // in a <style> in the <head> of the page, and if the stylesheet is a CSS module, it
          // exports a plain object of class names.
          if (args.pluginData?.importedFromJs) {
            const code = isCssModule ? contents.code : contents
            const mod = [
              `let e = document.querySelector('#_${hash}');`,
              'if (!e) {',
              "e = document.createElement('style');",
              `e.id = '_${hash}';`,
              'document.head.appendChild(e);',
              `e.appendChild(document.createComment('${relativePath}'));`,
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

async function digest(filePath) {
  let value = await Deno.realPath(filePath)
  value = new TextEncoder().encode(value)
  const view = new DataView(await crypto.subtle.digest('SHA-1', value))

  let hexCodes = ''
  for (let index = 0; index < view.byteLength; index += 4) {
    hexCodes += view.getUint32(index).toString(16).padStart(8, '0')
  }

  return hexCodes.slice(0, 8)
}

async function isViewComponent(path) {
  const fileName = basename(path)
  const dirName = dirname(path)

  return (
    (fileName === 'component.module.css' && (await fileExists(join(dirName, 'component.rb')))) ||
    (fileName.endsWith('_component.module.css') &&
      (await fileExists(join(dirName, fileName.replace(/\.module\.css$/, '.rb')))))
  )
}

async function getCustomMedia(cwd) {
  try {
    return await Deno.readTextFile(join(cwd, 'config', 'custom_media_queries.css'))
  } catch {
    // do nothing, as we don't require custom media.
  }
}

function cssModulesProxyTemplate(hash) {
  return [
    `export default new Proxy( {}, {`,
    `  get(target, prop, receiver) {`,
    `    if (prop in target || typeof prop === 'symbol') {`,
    `      return Reflect.get(target, prop, receiver)`,
    `    } else {`,
    `      return prop + '${hash}'`,
    `    }`,
    `  }`,
    `})`
  ].join('')
}
