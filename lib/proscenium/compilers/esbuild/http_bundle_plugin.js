import setup from './setup_plugin.js'

export default setup('httpBundle', () => {
  return [
    {
      type: 'onResolve',
      filter: /^https?:\/\//,
      callback(args) {
        let queryParams, suffix
        if (args.path.includes('?')) {
          const [path, query] = args.path.split('?')
          queryParams = new URLSearchParams(query)
          suffix = `?${query}`
          args.path = path
        }

        if (queryParams?.has('bundle')) {
          return { path: args.path, namespace: 'httpBundle', suffix }
        } else {
          return { external: true }
        }
      }
    },

    // Intercept all import paths inside downloaded files and resolve them against the original URL.
    {
      type: 'onResolve',
      filter: /.*/,
      namespace: 'httpBundle',
      callback(args) {
        return {
          path: new URL(args.path, args.importer).toString(),
          namespace: 'httpBundle'
        }
      }
    },

    // Download and return the content.
    //
    // TODO: cache this!
    {
      type: 'onLoad',
      filter: /.*/,
      namespace: 'httpBundle',
      async callback(args) {
        const textResponse = await fetch(args.path)
        const contents = await textResponse.text()

        return { contents }
      }
    }
  ]
})
