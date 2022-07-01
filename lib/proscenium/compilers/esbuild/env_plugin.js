import setup from './setup_plugin.js'

export default setup('env', () => {
  return {
    onResolve: {
      filter: /^env$/,
      callback({ path }) {
        return { path, namespace: 'env' }
      }
    },

    onLoad: {
      filter: /.*/,
      namespace: 'env',
      callback() {
        const env = Deno.env.toObject()
        return { loader: 'json', contents: JSON.stringify(env) }
      }
    }
  }
})
