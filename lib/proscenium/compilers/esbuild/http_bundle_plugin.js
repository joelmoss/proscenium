import setup from './setup_plugin.js'

// TODO: support bundling from import map
export default setup('httpBundle', () => {
  return {
    onResolve: {
      filter: /^https?:\/\//,
      callback(args) {
        let queryParams
        if (args.path.includes('?')) {
          const [, query] = args.path.split('?')
          queryParams = new URLSearchParams(query)
        }

        if (queryParams?.has('bundle')) {
          return { path: args.path, namespace: 'httpBundle' }
        } else {
          return { external: true }
        }
      }
    },

    onLoad: {
      filter: /.*/,
      namespace: 'httpBundle',
      async callback(args) {
        const textResponse = await fetch(args.path)
        const contents = await textResponse.text()

        return { loader: 'css', contents }
      }
    }
  }
})
