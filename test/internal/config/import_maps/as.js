env => ({
  imports: {
    pkg: env === 'test' ? '/lib/foo2.js' : '/lib/foo3.js'
  }
})
