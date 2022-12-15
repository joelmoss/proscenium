import 'bundle:foo' // import map
import 'bundle:/lib/foo2' // absolute path
import 'bundle:../foo3' // relative path
import 'bundle:mypackage' // bare module
import 'bundle:./nested' // nested import
import Component from 'bundle:../component.jsx' // jsx
import emailRegex from 'bundle:email-regex' // import map to URL - unsupported!
import emailRegex2 from 'bundle:https://esm.sh/email-regex' // URL - bundle: is ignored and passed though

Component()
emailRegex()
emailRegex2()
