import * as esbuild from 'https://deno.land/x/esbuild@v0.14.8/mod.js'
import { parse } from 'https://deno.land/std/flags/mod.ts'
import { join } from 'https://deno.land/std/path/mod.ts'

import resolvePlugin from './esbuild/resolve_plugin.js'

const isProd = Deno.env.get('RAILS_ENV') === 'production'
const template = `
<style>
:host {
  position: fixed;
  z-index: 99999;
  top: 0;
  left: 0;
  width: 100%;
  height: 100%;
  overflow-y: scroll;
  margin: 0;
  background: rgba(0, 0, 0, 0.66);
  display: flex;
  align-items: center;
  --monospace: 'SFMono-Regular', Consolas,
              'Liberation Mono', Menlo, Courier, monospace;
  --red: #ff5555;
  --yellow: #e2aa53;
  --purple: #cfa4ff;
  --cyan: #2dd9da;
  --dim: #c9c9c9;
}

.window {
  font-family: var(--monospace);
  line-height: 1.5;
  width: 800px;
  color: #d8d8d8;
  margin: 30px auto;
  padding: 25px 40px;
  position: relative;
  background: #181818;
  border-radius: 6px 6px 8px 8px;
  box-shadow: 0 19px 38px rgba(0,0,0,0.30), 0 15px 12px rgba(0,0,0,0.22);
  overflow: hidden;
  border-top: 8px solid var(--red);
}

pre {
  font-family: var(--monospace);
  font-size: 16px;
  margin-top: 0;
  margin-bottom: 1em;
  overflow-x: scroll;
  scrollbar-width: none;
}

pre::-webkit-scrollbar {
  display: none;
}

.message {
  line-height: 1.3;
  font-weight: 600;
  white-space: pre-wrap;
}

.message-body {
  color: var(--red);
}

.file {
  color: var(--cyan);
  margin-bottom: 0;
  white-space: pre-wrap;
  word-break: break-all;
}

</style>
<div class="window">
  <pre class="message"><span class="message-body"></span></pre>
  <pre class="file"></pre>
</div>
`

export default async args => {
  const { _: entrypoints, ...flags } = parse(args)
  const [cwd, entrypoint] = validatePaths(entrypoints)

  const params = {
    entryPoints: [entrypoint],
    absWorkingDir: cwd,
    logLevel: 'silent',
    write: false,
    format: 'esm',
    bundle: true,
    plugins: [resolvePlugin()]
  }

  if (entrypoint.endsWith('.jsx')) {
    try {
      const stat = Deno.lstatSync(join(cwd, 'lib/react_shim.js'))
      if (stat.isFile) {
        params.inject = ['./lib/react_shim.js']
      }
    } catch {
      // Safe to swallow as this should only throw if file does not exist.
    }
  }

  try {
    const result = await esbuild.build(params)
    return result.outputFiles[0].contents
  } catch (e) {
    if (isProd) {
      return new TextEncoder().encode(`
        const err = ${JSON.stringify(e.errors[0])}
        const location = \`\${err.location.file}:\${err.location.line}:\${err.location.column}\`
        console.error('%s at %O', err.text, location);
      `)
    } else {
      return new TextEncoder().encode(`
        class ErrorOverlay extends HTMLElement {
          constructor(err) {
            super()

            this.root = this.attachShadow({ mode: 'open' })
            this.root.innerHTML = \`${template}\`
            this.root.querySelector('.message-body').textContent = err.text.trim()

            if (err.location) {
              const location = \`\${err.location.file}:\${err.location.line}:\${err.location.column}\`
              this.root.querySelector('.file').textContent = location
              console.error('%s at %O', err.text, location)
            } else {
              console.error(err.text)
            }
          }
        }

        customElements.define('error-overlay', ErrorOverlay)
        document.body.appendChild(new ErrorOverlay(${JSON.stringify(e.errors[0])}))
      `)
    }
  } finally {
    esbuild.stop()
  }
}

function validatePaths(paths) {
  const cwd = paths[0]
  const entrypoint = paths[1]

  if (!cwd || !entrypoint) {
    throw new TypeError(
      'Current working directory and entrypoint are required first and second arguments.'
    )
  }

  try {
    const stat = Deno.lstatSync(cwd)
    if (!stat.isDirectory) {
      throw new TypeError(
        `Current working directory is required as the first argument - received ${cwd}`
      )
    }
  } catch {
    throw new TypeError(
      `A valid working directory is required as the first argument - received ${cwd}`
    )
  }

  try {
    const stat = Deno.lstatSync(join(cwd, entrypoint))
    if (!stat.isFile) {
      throw new TypeError(`Entrypoint is required as the second argument - received ${entrypoint}`)
    }
  } catch {
    throw new TypeError(
      `A valid entrypoint is required as the second argument - received ${entrypoint}`
    )
  }

  if (/\.(js|jsx)$/.test(entrypoint) === false) {
    throw new TypeError(
      `Only a JS/JSX entrypoint is supported with this CLI - received ${entrypoint}`
    )
  }

  return [cwd, entrypoint]
}
