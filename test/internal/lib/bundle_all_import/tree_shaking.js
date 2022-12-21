import { foo, bar } from 'bundle-all:./tree_shaking/index.js'
import foo3 from '/lib/foo3.js'
foo()
foo3()

// import { addMinutes } from 'bundle-all:date-fns'
// addMinutes()
