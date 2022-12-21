import one from 'bundle-all:./one'
import '/lib/foo.js' // should not be bundled

one()
