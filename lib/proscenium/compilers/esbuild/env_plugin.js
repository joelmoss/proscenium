import setup from './setup_plugin.js'

export default setup('env', () => {
  return [
    {
      type: 'onResolve',
      filter: /^env$/,
      callback({ path }) {
        return { path, namespace: 'env' }
      }
    },

    {
      type: 'onLoad',
      filter: /.*/,
      namespace: 'env',
      callback() {
        const env = Deno.env.toObject()
        return { loader: 'json', contents: JSON.stringify(env) }
      }
    }
  ]
})
