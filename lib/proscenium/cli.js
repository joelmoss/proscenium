import { writeAll } from 'https://deno.land/std/streams/conversion.ts'
import builder from './builder.js'

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

const [cwd, entrypoint] = Deno.args

try {
  const result = await builder(cwd, entrypoint)
  await writeAll(Deno.stdout, result.outputFiles[0].contents)
} catch (e) {
  let contentBytes
  if (isProd) {
    contentBytes = new TextEncoder().encode(`
      const err = ${JSON.stringify(e.errors[0])}
      const location = \`\${err.location.file}:\${err.location.line}:\${err.location.column}\`
      console.error('%s at %O', err.text, location);`)
  } else {
    contentBytes = new TextEncoder().encode(`
      class ErrorOverlay extends HTMLElement {
        constructor(err) {
          super()

          this.root = this.attachShadow({ mode: 'open' })
          this.root.innerHTML = \`${template}\`
          this.root.querySelector('.message-body').textContent = err.text.trim()
          const location = \`\${err.location.file}:\${err.location.line}:\${err.location.column}\`
          this.root.querySelector('.file').textContent = location

          console.error('%s at %O', err.text, location)
        }
      }

      customElements.define('error-overlay', ErrorOverlay)
      document.body.appendChild(new ErrorOverlay(${JSON.stringify(e.errors[0])}))
    `)
  }

  await writeAll(Deno.stdout, contentBytes)
}
