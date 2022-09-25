import 'foo?bundle' // import map
import '/lib/foo2?bundle' // absolute path
import './foo3?bundle' // relative path
import 'mypackage?bundle' // bare module
import './import_proscenium_component_manager?bundle' // nested import
import Component from './component.jsx?bundle' // jsx
import emailRegex from 'email-regex?bundle' // import map to URL - unsupported!
import emailRegex2 from 'https://esm.sh/email-regex?bundle' // URL - ?bundle is ignored and passed though

Component()
emailRegex()
emailRegex2()
