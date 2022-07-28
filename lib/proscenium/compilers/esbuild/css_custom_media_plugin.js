import setup from './setup_plugin.js'

export default setup('cssCustomMedia', () => {
  return {
    // onResolve: {
    //   filter: /^env$/,
    //   callback({ path }) {
    //     return { path, namespace: 'env' }
    //   }
    // },

    onLoad: {
      filter: /\.css$/,
      callback() {
        const env = Deno.env.toObject()
        return { loader: 'json', contents: JSON.stringify(env) }
      }
    }
  }
})
