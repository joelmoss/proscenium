import foo from 'bundle:./foo.js' // relative path
import 'bundle:../foo3' // relative path without extension
import 'bundle:foo' // import map
import foo4 from 'bundle:foo4' // import map
import 'bundle:/lib/foo2' // absolute path
import 'bundle:mypackage' // bare module
import 'bundle:./nested' // nested import
import Component from 'bundle:../component.jsx' // jsx
import emailRegex from 'bundle:email-regex' // import map to URL
import ipRegex from 'bundle:https://esm.sh/v99/ip-regex@5.0.0/es2022/ip-regex.js' // URL

foo()
foo4()
Component()
emailRegex()
ipRegex()
