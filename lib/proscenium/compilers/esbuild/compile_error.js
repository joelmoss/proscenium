export default function () {
  if (Deno.env.get('RAILS_ENV') === 'development') {
    return function (detail) {
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
            margin: 0 0 1em 0;
            overflow-x: scroll;
            scrollbar-width: none;
          }

          pre::-webkit-scrollbar {
            display: none;
          }

          .title, .message {
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

          .code {
            background: black;
            border-left: 3px solid gray;
            padding: 10px 0 0 20px;
          }
          .lineText {
            white-space: pre-wrap;
          }
          .lineCursor {
            white-space: pre;
            color: blueviolet;
          }
        </style>
        <div class="window">
          <pre class="title">COMPILE ERROR!</pre>
          <pre class="message"><span class="message-body"></span> in <span class="file"></span></pre>
          <pre class="code"><span class="lineText"></span><span class="lineCursor"></span></pre>
        </div>
      `

      class ErrorOverlay extends HTMLElement {
        constructor(err) {
          super()

          this.root = this.attachShadow({ mode: 'open' })
          this.root.innerHTML = template
          this.root.querySelector('.message-body').textContent = err.text.trim()
          if (err.location) {
            const location = `/${err.location.file}:${err.location.line}:${err.location.column}`
            this.root.querySelector('.file').textContent = location
            this.root.querySelector('.lineText').textContent = err.location.lineText
            this.root.querySelector('.lineCursor').textContent =
              ''.padStart(err.location.column - 1, ' ') + '^'
            console.error('%s at %O', err.text, location)
          } else {
            console.error(err.text)
          }

          this.root.querySelector('.window').addEventListener('click', e => {
            e.stopPropagation()
          })

          this.addEventListener('click', () => {
            this.close()
          })
        }

        close() {
          this.parentNode?.removeChild(this)
        }
      }

      const overlayId = 'proscenium-error-overlay'
      if (customElements && !customElements.get(overlayId)) {
        customElements.define(overlayId, ErrorOverlay)
      }

      document.body.appendChild(new ErrorOverlay(detail))
    }
  } else {
    return function (detail) {
      const location = `/${detail.location.file}:${detail.location.line}:${detail.location.column}`
      console.error('%s at %O', detail.text, location)
      throw `${detail.text} at ${location}`
    }
  }
}
