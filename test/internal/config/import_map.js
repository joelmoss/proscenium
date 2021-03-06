env => ({
  imports: {
    react:
      env === 'development' ? 'https://esm.sh/react@18.2.0?dev' : 'https://esm.sh/react@18.2.0',
    'react-dom/client':
      env === 'development'
        ? 'https://esm.sh/react-dom@18.2.0/client?dev'
        : 'https://esm.sh/react-dom@18.2.0/client',
    'react/jsx-runtime': 'https://esm.sh/react@18.2.0/jsx-runtime',
    foo: '/lib/foo.js',
    solid: 'https://esm.sh/solid@0.2.1',
    axios: 'https://cdnjs.cloudflare.com/ajax/libs/axios/0.24.0/axios.min.js'
  }
})
