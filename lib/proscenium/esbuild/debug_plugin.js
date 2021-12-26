export default {
  name: 'debug',
  setup(build) {
    build.onResolve({ filter: /.*/ }, args => {
      console.debug('onResolve', args)
    })
    build.onLoad({ filter: /.*/ }, args => {
      console.debug('onLoad', args)
    })
  }
}
