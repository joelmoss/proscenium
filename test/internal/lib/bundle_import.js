import 'foo?bundle' // import map
import '/lib/foo2?bundle' // absolute path
import './foo3?bundle' // relative path
import 'mypackage?bundle' // bare module
import './import_proscenium_component_manager?bundle' // nested import
// import 'https://cdnjs.cloudflare.com/ajax/libs/axios/0.24.0/axios.min.js?bundle'
import Component from './component.jsx?bundle' // jsx

Component()
