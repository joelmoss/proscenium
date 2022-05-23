import { createConsumer } from 'https://esm.sh/@rails/actioncable'
import debounce from 'https://esm.sh/debounce'

if (window.SOCKET_PATH) {
  const uid = (Date.now() + ((Math.random() * 100) | 0)).toString()
  const consumer = createConsumer(`${window.SOCKET_PATH}?uid=${uid}`)

  consumer.subscriptions.create('Proscenium::ReloadChannel', {
    received: debounce(data => {
      console.log('Proscenium files changed; reloading...')
      location.reload()
    }, 200),

    connected() {
      console.log('Proscenium auto reload websocket connected')
    },

    disconnected() {
      console.log('Proscenium auto reload websocket disconnected')
    }
  })
}
