import setup from './setup_plugin.js'
// import { transform } from 'https://esm.sh/cjstoesm@2.1.2'

export default setup('cjs', () => {
  return [
    {
      type: 'onLoad',
      filter: /\.js$/,
      async callback(args) {
        const esm = await transform({ input: args.path, write: false, debug: true })
        console.log(esm)
        throw '??'
      }
    }
  ]
})
