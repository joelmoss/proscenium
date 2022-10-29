import setup from './setup_plugin.js'

// Export environment variables as named exports only. You can also import from `env:ENV_VAR_NAME`,
// which will return the value of the environment variable as the default export. This allows you to
// safely import a variable regardless of its existence.
export default setup('env', () => {
  return [
    {
      type: 'onResolve',
      filter: /^env(:.+)?$/,
      callback({ path }) {
        return { path, namespace: 'env' }
      }
    },

    {
      type: 'onLoad',
      filter: /.*/,
      namespace: 'env',
      callback({ path }) {
        if (path.includes(':')) {
          const name = Deno.env.get(path.split(':')[1])

          return {
            loader: 'js',
            contents: name ? `export default '${name}'` : `export default ${name}`
          }
        }

        const env = Deno.env.toObject()
        const contents = []

        for (const key in env) {
          if (Object.hasOwnProperty.call(env, key)) {
            contents.push(`export const ${key} = '${env[key]}'`)
          }
        }

        return {
          loader: 'js',
          contents: contents.join(';')
        }
      }
    }
  ]
})
