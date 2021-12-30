import { setup } from '../utils.js'

export default setup('css', build => {
  const cwd = build.initialOptions.absWorkingDir

  return {
    onResolve: {
      filter: /\.css$/,
      callback(args) {
        if (args.kind === 'import-statement' && args.importer.endsWith('js')) {
          return {
            path: args.path,
            namespace: 'appendStylesheet'
            // path: `${args.path}.js`,
            // external: true
          }
        }
      }
    },

    onLoad: {
      filter: /\.css$/,
      callback(args) {
        return {
          contents: `
          import appendStylesheet from 'appendStylesheet'
          appendStylesheet("${args.path.slice(cwd.length)}")
        `,
          loader: 'js'
        }
      }
    }
  }
})

export const appendStylesheetPlugin = setup('appendStylesheet', () => {
  return {
    onResolve: {
      filter: /^appendStylesheet$/,
      callback: args => {
        console.log(3, args)
        return {
          path: 'appendStylesheet',
          namespace: 'appendStylesheetShim'
        }
      }
    },

    onLoad: {
      filter: /^appendStylesheet$/,
      namespace: 'appendStylesheetShim',
      callback: args => {
        console.log(4, args)
        return {
          contents: `
          export default function (path) {
            const ele = document.createElement('link')
            ele.setAttribute('rel', 'stylesheet')
            ele.setAttribute('media', 'all')
            ele.setAttribute('href', path)
            document.head.appendChild(ele)
          }
        `
        }
      }
    }
  }
})
