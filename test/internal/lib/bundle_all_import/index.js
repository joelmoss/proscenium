import one from 'bundle-all:./one'
import foo4 from '/lib/foo4.js' // should not be bundled

one()
foo4()
